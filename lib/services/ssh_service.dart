import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart' show Terminal;
import 'agent_forward_service.dart';

enum SshAuthMethod { password, key, agent }

/// Result type for host-key verification injected into [SshConnectionConfig].
/// Throwing [HostKeyMismatchException] / [UnknownHostException] from the
/// callback lets the caller surface a trust prompt to the user.
class HostKeyMismatchException implements Exception {
  final String host;
  final int port;
  final String keyType;
  final String fingerprint;
  HostKeyMismatchException(this.host, this.port, this.keyType, this.fingerprint);
  @override
  String toString() =>
      'Host key for $host:$port has changed! Possible MITM. '
      '($keyType $fingerprint)';
}

class UnknownHostException implements Exception {
  final String host;
  final int port;
  final String keyType;
  final String fingerprint;
  UnknownHostException(this.host, this.port, this.keyType, this.fingerprint);
  @override
  String toString() =>
      'Unknown host $host:$port ($keyType $fingerprint). '
      'Trust it before connecting.';
}

class SshConnectionConfig {
  final String host;
  final int port;
  final String username;
  final SshAuthMethod authMethod;
  final String? password;
  final String? privateKeyPem;
  final String? passphrase;

  /// Verifies the server's host key. Receives the key type and a raw
  /// fingerprint (as dartssh2 provides). Return true to accept, false (or
  /// throw) to reject. When null, host keys are NOT verified — preserved for
  /// backward compatibility with existing tests, but production callers
  /// should always supply one.
  final FutureOr<bool> Function(String type, Uint8List fingerprint)?
      onVerifyHostKey;

  SshConnectionConfig({
    required this.host,
    this.port = 22,
    required this.username,
    required this.authMethod,
    this.password,
    this.privateKeyPem,
    this.passphrase,
    this.onVerifyHostKey,
  });
}

/// Transport seam so the session lifecycle (connect / reconnect / teardown)
/// can be driven by tests without a real SSH server.
abstract interface class SshTransport {
  Future<void> connect(SshConnectionConfig config);
  void writeToTerminal(String data);
  void resizeTerminal(int width, int height);
  void dispose();
  Stream<String> get output;
  Stream<bool> get connectionState;
  bool get isConnected;
}

class SshService implements SshTransport {
  SSHClient? _client;
  SSHSession? _session;

  /// Resize requested while no session existed yet (the view lays out and
  /// resizes the terminal before/while connect() is still running). Applied
  /// as soon as the shell channel opens so the remote pty geometry matches
  /// the local terminal from the start; otherwise the remote stays at the
  /// initial size and screen-clearing sequences only wipe part of the view.
  int? _pendingWidth;
  int? _pendingHeight;

  final StreamController<String> _outputController =
      StreamController.broadcast();
  final StreamController<bool> _connectionController =
      StreamController.broadcast();
  StreamSubscription<Uint8List>? _stdoutSubscription;
  StreamSubscription<Uint8List>? _stderrSubscription;
  bool _disposed = false;

  /// Opt-in wire tracing for diagnosing terminal-compat issues: set
  /// PICSHELL_SSH_TRACE=1 when launching the app and every output chunk
  /// (pretty-printed) is appended to `Documents/picshell_ssh_trace.log`.
  static final bool _traceEnabled =
      Platform.environment['PICSHELL_SSH_TRACE'] == '1';
  static IOSink? _traceSink;

  void _trace(String direction, Uint8List data) {
    if (!_traceEnabled) return;
    _ensureTraceSink();
    final sb = StringBuffer();
    final now = DateTime.now();
    sb.write('${now.hour}:${now.minute}:${now.second}.${now.millisecond} '
        '$direction: ');
    var inEsc = false;
    for (final b in data) {
      if (b == 0x1b) {
        sb.write('<ESC>');
        inEsc = true;
      } else if (inEsc) {
        sb.write(String.fromCharCode(b));
        if ((b >= 0x40 && b <= 0x7e) || b == 0x07) {
          sb.write(' ');
          inEsc = false;
        }
      } else if (b == 0x0d) {
        sb.write('<CR>');
      } else if (b == 0x0a) {
        sb.write('<LF>');
      } else {
        sb.write(String.fromCharCode(b));
      }
    }
    sb.writeln();
    _traceSink!.write(sb.toString());
  }

  /// Logs the emulator's cursor/viewport state after a chunk is applied.
  static void traceCursorState(Terminal terminal) {
    if (!_traceEnabled) return;
    _ensureTraceSink();
    final cur = terminal.buffer;
    final now = DateTime.now();
    _traceSink!.writeln(
        '${now.hour}:${now.minute}:${now.second}.${now.millisecond} '
        '[cursor] x=${cur.cursorX} y=${cur.cursorY} '
        'view=${terminal.viewWidth}x${terminal.viewHeight} '
        'hash=${identityHashCode(terminal)}');
  }

  static void traceEvent(String message) {
    if (!_traceEnabled) return;
    _ensureTraceSink();
    _traceSink!.writeln(
        '${DateTime.now().hour}:${DateTime.now().minute}:'
        '${DateTime.now().second}.${DateTime.now().millisecond} '
        '[event] $message');
  }

  static void _ensureTraceSink() {
    // Append-only: never delete here — this runs inside layout paths and a
    // failed delete would abort the resize. Clear the file externally.
    _traceSink ??= File('${_traceDir()}/picshell_ssh_trace.log')
        .openWrite(mode: FileMode.append);
  }

  static String _traceDir() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return home == null ? '.' : '$home/Documents';
  }

  /// Splits a byte stream on UTF-8 sequence boundaries. Decoding each TCP
  /// chunk in isolation corrupts any multibyte character (CJK, emoji) that
  /// straddles two reads into U+FFFD replacement characters.
  final _Utf8StreamDecoder _utf8 = _Utf8StreamDecoder();

  @override
  Stream<String> get output => _outputController.stream;
  @override
  Stream<bool> get connectionState => _connectionController.stream;
  @override
  bool get isConnected => _client != null && _session != null;

  void _safeAddOutput(String data) {
    if (!_disposed && !_outputController.isClosed) {
      _outputController.add(data);
    }
  }

  void _safeAddConnection(bool value) {
    if (!_disposed && !_connectionController.isClosed) {
      _connectionController.add(value);
    }
  }

  @override
  Future<void> connect(SshConnectionConfig config) async {
    SSHSocket? socket;
    SSHClient? client;
    try {
      socket = await SSHSocket.connect(config.host, config.port);

      switch (config.authMethod) {
        case SshAuthMethod.password:
          client = SSHClient(
            socket,
            username: config.username,
            onPasswordRequest: () => config.password ?? '',
            onVerifyHostKey: config.onVerifyHostKey,
          );
          break;
        case SshAuthMethod.key:
          final keyPair = SSHKeyPair.fromPem(
            config.privateKeyPem!,
            config.passphrase,
          );
          client = SSHClient(
            socket,
            username: config.username,
            identities: keyPair,
            onVerifyHostKey: config.onVerifyHostKey,
          );
          break;
        case SshAuthMethod.agent:
          final agentClient = await AgentForwardService.connectWithAgent(
            host: config.host,
            port: config.port,
            username: config.username,
            onVerifyHostKey: config.onVerifyHostKey,
          );
          if (agentClient != null) {
            client = agentClient;
          } else {
            throw Exception('No SSH keys found in ~/.ssh/');
          }
          break;
      }

      _client = client;
      _session = await _client!.shell(
        pty: const SSHPtyConfig(width: 120, height: 30, type: 'xterm-256color'),
      );
      if (_pendingWidth != null && _pendingHeight != null) {
        _session!.resizeTerminal(_pendingWidth!, _pendingHeight!);
        _pendingWidth = null;
        _pendingHeight = null;
      }

      _stdoutSubscription = _session!.stdout.listen(
        (Uint8List data) {
          _trace('OUT', data);
          _safeAddOutput(_utf8.process(data));
        },
        onError: (_) {
          _safeAddConnection(false);
        },
        onDone: () {
          _safeAddConnection(false);
        },
      );

      _stderrSubscription = _session!.stderr.listen(
        (Uint8List data) => _safeAddOutput(_utf8.process(data)),
        onError: (_) {},
      );

      _safeAddConnection(true);
    } catch (e) {
      // Close anything half-open so failed attempts don't leak sockets.
      try {
        client?.close();
      } catch (_) {}
      if (client == null) {
        try {
          socket?.close();
        } catch (_) {}
      }
      _client = null;
      _session = null;
      _safeAddConnection(false);
      rethrow;
    }
  }

  @override
  void writeToTerminal(String data) {
    _trace('IN ', utf8.encode(data));
    _session?.write(utf8.encode(data));
  }

  @override
  void resizeTerminal(int width, int height) {
    if (_session == null) {
      _pendingWidth = width;
      _pendingHeight = height;
      return;
    }
    _session!.resizeTerminal(width, height);
  }

  void disconnect() {
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _session?.close();
    _client?.close();
    _client = null;
    _session = null;
    _safeAddConnection(false);
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    if (!_outputController.isClosed) _outputController.close();
    if (!_connectionController.isClosed) _connectionController.close();
  }
}

/// Accumulates SSH output bytes and decodes them on UTF-8 sequence
/// boundaries, holding back trailing incomplete sequences until the rest
/// arrives (or the stream ends).
class _Utf8StreamDecoder {
  final List<int> _pending = [];

  String process(Uint8List data) {
    final Uint8List bytes;
    if (_pending.isEmpty) {
      bytes = data;
    } else {
      bytes = Uint8List.fromList([..._pending, ...data]);
      _pending.clear();
    }

    // Inspect the tail: walk back over continuation bytes (0b10xxxxxx) to the
    // lead byte of a possibly-truncated final sequence.
    var holdback = 0;
    final scanStart = bytes.length >= 4 ? bytes.length - 4 : 0;
    for (var i = bytes.length - 1; i >= scanStart; i--) {
      final b = bytes[i];
      if (b & 0xC0 != 0x80) {
        final expected =
            b >= 0xF0 ? 3 : (b >= 0xE0 ? 2 : (b >= 0xC0 ? 1 : 0));
        final continuations = bytes.length - 1 - i;
        holdback = continuations < expected ? continuations + 1 : 0;
        break;
      }
    }
    // If the whole 4-byte window is continuation bytes the sequence start is
    // older than the window; decode as-is and let the replacement character
    // mark the corruption rather than buffering forever.

    if (holdback > 0) {
      _pending.addAll(bytes.sublist(bytes.length - holdback));
    }

    final end = bytes.length - holdback;
    if (end <= 0) return '';
    return utf8.decode(
      Uint8List.sublistView(bytes, 0, end),
      allowMalformed: true,
    );
  }
}
