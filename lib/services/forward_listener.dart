import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/forward_rule.dart';

/// A running port forward bound to a session's [SSHClient].
///
/// Wraps the type-specific listener state (a [ServerSocket] for local, an
/// [SSHRemoteForward] for remote) and offers a uniform [stop] regardless of
/// [ForwardType]. Created via [ActiveForward.bind].
abstract class ActiveForward {
  final String ruleId;
  final ForwardType type;

  /// Port actually bound. When [ForwardRule.localPort] was 0 the OS picked a
  /// free port; this reports the real value so the UI can display it.
  final int boundPort;

  ActiveForward(this.ruleId, this.type, this.boundPort);

  Future<void> stop();

  /// Builds the appropriate forward for [rule] on [client]. Throws if [client]
  /// is not yet authenticated or the requested port is already in use.
  static Future<ActiveForward> bind(SSHClient client, ForwardRule rule) {
    switch (rule.type) {
      case ForwardType.local:
        return _LocalForward.bind(client, rule);
      case ForwardType.remote:
        return _RemoteForward.bind(client, rule);
      case ForwardType.socks:
        return _DynamicForward.bind(client, rule);
    }
  }
}

/// Bidirectionally pipes a local [Socket] to an [SSHForwardChannel]. Either
/// side closing or erroring tears down both. Used by local and remote forwards.
void _pipe(Socket socket, SSHForwardChannel channel) {
  void teardown() {
    socket.destroy();
    channel.close();
  }

  socket.listen(
    (data) => channel.sink.add(data),
    onError: (_) => teardown(),
    onDone: teardown,
  );
  channel.stream.listen(
    (data) => socket.add(data),
    onError: (_) => teardown(),
    onDone: teardown,
  );
}

/// Local forward (`ssh -L`). Binds a [ServerSocket] on the client and, for
/// every incoming connection, opens a `direct-tcpip` channel via
/// [SSHClient.forwardLocal] and pipes it through. dartssh2's `forwardLocal`
/// is per-connection only, so the listener glue lives here.
class _LocalForward extends ActiveForward {
  final ServerSocket _server;

  _LocalForward._(this._server, String ruleId)
      : super(ruleId, ForwardType.local, _server.port);

  static Future<_LocalForward> bind(SSHClient client, ForwardRule rule) async {
    final remoteHost = rule.remoteHost;
    final remotePort = rule.remotePort;
    if (remoteHost == null || remotePort == null) {
      throw ArgumentError(
        'Local forward requires remoteHost and remotePort (rule ${rule.id})',
      );
    }
    final server = await ServerSocket.bind(rule.localHost, rule.localPort);
    server.listen(
      (socket) async {
        try {
          final channel = await client.forwardLocal(remoteHost, remotePort);
          _pipe(socket, channel);
        } catch (_) {
          socket.destroy();
        }
      },
      onError: (_) {},
    );
    return _LocalForward._(server, rule.id);
  }

  @override
  Future<void> stop() => _server.close();
}

/// Remote forward (`ssh -R`). Asks the server to listen on a port; for each
/// incoming server-side connection dartssh2 emits an [SSHForwardChannel] on
/// [SSHRemoteForward.connections], which we pipe to a local TCP socket.
class _RemoteForward extends ActiveForward {
  final SSHRemoteForward _forward;
  final StreamSubscription<SSHForwardChannel> _sub;

  _RemoteForward._(this._forward, this._sub, String ruleId, int boundPort)
      : super(ruleId, ForwardType.remote, boundPort);

  static Future<_RemoteForward> bind(SSHClient client, ForwardRule rule) async {
    final targetHost = rule.remoteHost;
    final targetPort = rule.remotePort;
    if (targetHost == null || targetPort == null) {
      throw ArgumentError(
        'Remote forward requires remoteHost and remotePort '
        '(the local endpoint to dial back to, rule ${rule.id})',
      );
    }
    final forward = await client.forwardRemote(port: rule.localPort);
    if (forward == null) {
      throw StateError(
        'Server refused remote forward on port ${rule.localPort}',
      );
    }
    final sub = forward.connections.listen((channel) async {
      try {
        final local = await Socket.connect(targetHost, targetPort);
        _pipe(local, channel);
      } catch (_) {
        channel.close();
      }
    });
    return _RemoteForward._(forward, sub, rule.id, forward.port);
  }

  @override
  Future<void> stop() async {
    await _sub.cancel();
    // SSHRemoteForward.close is synchronous (void); it kicks off
    // cancelForwardRemote internally without awaiting.
    _forward.close();
  }
}

/// Dynamic SOCKS5 forward (`ssh -D`). Binds a [ServerSocket] on the client
/// that speaks the SOCKS5 protocol (NO AUTH + CONNECT only); for each request
/// it opens a `direct-tcpip` channel via [SSHClient.forwardLocal] and pipes the
/// data through. Implemented by hand rather than via dartssh2's `forwardDynamic`
/// to avoid the pointycastle 4.x upgrade that API requires.
class _DynamicForward extends ActiveForward {
  final ServerSocket _server;
  final Set<_SocksConn> _conns = {};

  _DynamicForward._(this._server, String ruleId)
      : super(ruleId, ForwardType.socks, _server.port);

  static Future<_DynamicForward> bind(SSHClient client, ForwardRule rule) async {
    final server = await ServerSocket.bind(rule.localHost, rule.localPort);
    final fwd = _DynamicForward._(server, rule.id);
    server.listen(
      (socket) {
        final conn = _SocksConn(socket);
        fwd._conns.add(conn);
        conn.done.whenComplete(() => fwd._conns.remove(conn));
        conn.negotiate(client);
      },
      onError: (_) {},
    );
    return fwd;
  }

  @override
  Future<void> stop() async {
    await _server.close();
    for (final c in List.of(_conns)) {
      c.close();
    }
  }
}

/// One SOCKS5 client connection. Owns the socket's single subscription, so it
/// serves dual duty: [negotiate] reads the handshake from a buffered stream,
/// then the same subscription forwards payload bytes to the SSH channel once
/// attached (no second listener on the socket).
class _SocksConn {
  final Socket socket;
  final List<int> _buf = [];
  Completer<void>? _fill;
  bool _closed = false;
  late final StreamSubscription<Uint8List> _sub;
  SSHForwardChannel? _channel;
  final Completer<void> _done = Completer<void>();

  _SocksConn(this.socket) {
    _sub = socket.cast<Uint8List>().listen(
      (Uint8List data) {
        if (_channel != null) {
          // Piping mode: forward straight to the remote channel.
          _channel!.sink.add(data);
        } else {
          _buf.addAll(data);
          _fill?.complete();
          _fill = null;
        }
      },
      onError: (_) => close(),
      onDone: () => close(),
    );
  }

  /// Resolves when the connection is fully torn down.
  Future<void> get done => _done.future;

  /// Reads exactly [n] bytes, awaiting more socket data as needed. Throws if
  /// the peer closes before enough bytes arrive.
  Future<Uint8List> read(int n) async {
    while (_buf.length < n) {
      if (_closed) {
        throw const SocketException('SOCKS peer closed during handshake');
      }
      _fill = Completer<void>();
      await _fill!.future;
      _fill = null;
    }
    final out = Uint8List.fromList(_buf.sublist(0, n));
    _buf.removeRange(0, n);
    return out;
  }

  /// Runs the SOCKS5 method-selection + CONNECT handshake, then opens a
  /// direct-tcpip channel and switches this connection into piping mode.
  Future<void> negotiate(SSHClient client) async {
    try {
      // 1. Method selection: VER NMETHODS METHODS...
      final ver = await read(1);
      if (ver[0] != 0x05) {
        throw const _SocksError('not SOCKS5');
      }
      final nMethods = (await read(1))[0];
      final methods = await read(nMethods);
      if (!methods.contains(0x00)) {
        // No acceptable methods — we only support NO AUTH (0x00). The method
        // selection reply is exactly 2 bytes: VER METHOD.
        socket.add(Uint8List.fromList([0x05, 0xFF]));
        throw const _SocksError('no acceptable auth method');
      }
      // Select NO AUTH. The method-selection reply is 2 bytes (VER METHOD),
      // distinct from the 10-byte command reply [_socksReply].
      socket.add(Uint8List.fromList([0x05, 0x00]));

      // 2. Request: VER CMD RSV ATYP DST.ADDR DST.PORT
      final req = await read(4);
      if (req[0] != 0x05) {
        throw const _SocksError('bad request version');
      }
      if (req[1] != 0x01) {
        // Only CONNECT (0x01) is supported.
        socket.add(_socksReply(0x07)); // command not supported
        throw const _SocksError('only CONNECT supported');
      }
      final atyp = req[3];
      final String host;
      switch (atyp) {
        case 0x01: // IPv4
          final a = await read(4);
          host = '${a[0]}.${a[1]}.${a[2]}.${a[3]}';
        case 0x03: // domain
          final len = (await read(1))[0];
          host = utf8.decode(await read(len));
        case 0x04: // IPv6 — format 16 bytes as colon-separated hex groups.
          final a = await read(16);
          final groups = <String>[];
          for (var i = 0; i < 16; i += 2) {
            groups.add(((a[i] << 8) | a[i + 1]).toRadixString(16));
          }
          host = groups.join(':');
        default:
          socket.add(_socksReply(0x08)); // address type not supported
          throw const _SocksError('unsupported address type');
      }
      final pb = await read(2);
      final port = (pb[0] << 8) | pb[1];

      // 3. Open the direct-tcpip channel and report success/failure.
      final SSHForwardChannel channel;
      try {
        channel = await client.forwardLocal(host, port);
      } catch (_) {
        // Distinguish nothing further — remote host unreachable / refused.
        socket.add(_socksReply(0x04)); // host unreachable
        rethrow;
      }
      socket.add(_socksReply(0x00)); // succeeded
      _attach(channel);
    } catch (_) {
      close();
    }
  }

  /// Switches to piping mode: future socket bytes go to [channel], channel
  /// bytes go to the socket, leftover handshake buffer is flushed first.
  /// Synchronous (no await) so it is atomic w.r.t. the event loop.
  void _attach(SSHForwardChannel channel) {
    _channel = channel;
    if (_buf.isNotEmpty) {
      channel.sink.add(Uint8List.fromList(_buf));
      _buf.clear();
    }
    channel.stream.listen(
      (Uint8List data) {
        if (!_closed) socket.add(data);
      },
      onError: (_) => close(),
      onDone: close,
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _fill?.complete();
    _fill = null;
    _sub.cancel();
    _channel?.close();
    socket.destroy();
    if (!_done.isCompleted) _done.complete();
  }
}

/// A SOCKS5 reply: VER(5) REP RSV ATYP(1=IPv4) BND.ADDR(0.0.0.0) BND.PORT(0).
/// The bound address/port are reported as zeroes because picshell does not
/// expose the actual local bind to the SOCKS client.
Uint8List _socksReply(int rep) =>
    Uint8List.fromList([0x05, rep, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);

class _SocksError implements Exception {
  final String message;
  const _SocksError(this.message);
  @override
  String toString() => '_SocksError: $message';
}
