import 'dart:async';
import 'dart:io';

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
  ///
  /// [ForwardType.socks] currently throws [UnsupportedError]: it needs
  /// `dartssh2 >= 2.17` (`forwardDynamic`), which is held back by picshell's
  /// `pointycastle ^3.9.0` constraint. The enum value is kept so config imports
  /// can still record `DynamicForward` rules; they become usable once the
  /// pointycastle upgrade lands.
  static Future<ActiveForward> bind(SSHClient client, ForwardRule rule) {
    switch (rule.type) {
      case ForwardType.local:
        return _LocalForward.bind(client, rule);
      case ForwardType.remote:
        return _RemoteForward.bind(client, rule);
      case ForwardType.socks:
        throw UnsupportedError(
          'SOCKS5 dynamic forward (ssh -D) requires dartssh2 >= 2.17, which is '
          'currently held back by pointycastle ^3.9.0. The rule is preserved '
          'and will work once the dependency upgrade lands.',
        );
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
