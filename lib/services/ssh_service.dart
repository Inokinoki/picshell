import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/forward_rule.dart';
import 'agent_forward_service.dart';
import 'forward_listener.dart';

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

  /// Optional nested config for a jump host (ProxyJump, `ssh -J`). When set,
  /// [SshService.connect] first authenticates to the proxy, then opens a
  /// direct-tcpip channel through it to reach [host]:[port]. Nested so that
  /// future multi-hop chains can be expressed as proxyConfig.proxyConfig.
  /// Production callers must populate [onVerifyHostKey] on every hop —
  /// [SessionListNotifier.openSession] does this for both hops.
  final SshConnectionConfig? proxyConfig;

  SshConnectionConfig({
    required this.host,
    this.port = 22,
    required this.username,
    required this.authMethod,
    this.password,
    this.privateKeyPem,
    this.passphrase,
    this.onVerifyHostKey,
    this.proxyConfig,
  });
}

class SshService {
  SSHClient? _client;
  /// Jump host client (ProxyJump first hop), if any. Closed alongside [_client]
  /// in [disconnect]. Null for direct connections.
  SSHClient? _jumpClient;
  SSHSession? _session;
  final StreamController<String> _outputController =
      StreamController.broadcast();
  final StreamController<bool> _connectionController =
      StreamController.broadcast();
  StreamSubscription<Uint8List>? _stdoutSubscription;
  StreamSubscription<Uint8List>? _stderrSubscription;
  /// Active forwards keyed by their [ForwardRule.id]. Torn down on disconnect.
  final Map<String, ActiveForward> _activeForwards = {};
  bool _disposed = false;

  Stream<String> get output => _outputController.stream;
  Stream<bool> get connectionState => _connectionController.stream;
  bool get isConnected => _client != null && _session != null;

  /// The live SSH client, or null when not connected. Exposed so the session
  /// layer can attach forwards and ProxyJump channels; SFTP support opens a
  /// subsystem on it too. Callers must re-acquire it after a reconnect (which
  /// replaces `_client`). Returns null once [disconnect] / [dispose] has run.
  SSHClient? get client => _client;

  /// Read-only view of currently running forwards (for UI status).
  Map<String, ActiveForward> get activeForwards =>
      Map.unmodifiable(_activeForwards);

  /// Starts [rule] on the current client. Returns the actually bound port
  /// (which may differ from [ForwardRule.localPort] when 0 was requested).
  /// Throws if the client is not connected or the rule is already running.
  Future<int> startForward(ForwardRule rule) async {
    final client = _client;
    if (client == null) {
      throw StateError('Cannot start forward: SSH client not connected');
    }
    if (_activeForwards.containsKey(rule.id)) {
      return _activeForwards[rule.id]!.boundPort;
    }
    final forward = await ActiveForward.bind(client, rule);
    _activeForwards[rule.id] = forward;
    return forward.boundPort;
  }

  /// Stops a running forward by its rule id. No-op if not running.
  Future<void> stopForward(String ruleId) async {
    final forward = _activeForwards.remove(ruleId);
    if (forward != null) await forward.stop();
  }


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

  void _safeAddConnectionError(Object e) {
    if (!_disposed && !_connectionController.isClosed) {
      _connectionController.addError(e);
    }
  }

  Future<void> connect(SshConnectionConfig config) async {
    try {
      _safeAddConnection(false);

      // ProxyJump: authenticate to the jump host first, then open a
      // direct-tcpip channel through it which becomes the target's socket.
      // dartssh2's SSHForwardChannel implements SSHSocket, so it composes
      // cleanly as the transport for the next SSHClient.
      final SSHSocket socket;
      if (config.proxyConfig != null) {
        final proxy = config.proxyConfig!;
        final jumpSocket = await SSHSocket.connect(proxy.host, proxy.port);
        final jumpClient = _buildClient(jumpSocket, proxy);
        await jumpClient.authenticated;
        _jumpClient = jumpClient;
        socket = await jumpClient.forwardLocal(config.host, config.port);
      } else {
        socket = await SSHSocket.connect(config.host, config.port);
      }

      // Agent auth reads ~/.ssh and dials its own socket, so it only works for
      // direct connections. ProxyJump + agent is rejected in _buildClient.
      SSHClient client;
      if (config.proxyConfig == null &&
          config.authMethod == SshAuthMethod.agent) {
        final agentClient = await AgentForwardService.connectWithAgent(
          host: config.host,
          port: config.port,
          username: config.username,
          onVerifyHostKey: config.onVerifyHostKey,
        );
        if (agentClient == null) {
          throw Exception('No SSH keys found in ~/.ssh/');
        }
        client = agentClient;
      } else {
        client = _buildClient(socket, config);
      }

      _client = client;
      _session = await client.shell(
        pty: const SSHPtyConfig(width: 80, height: 24, type: 'xterm-256color'),
      );

      _stdoutSubscription = _session!.stdout.listen(
        (Uint8List data) => _safeAddOutput(utf8.decode(data, allowMalformed: true)),
        onError: (e) {
          _safeAddConnection(false);
        },
        onDone: () {
          _safeAddConnection(false);
        },
      );

      _stderrSubscription = _session!.stderr.listen(
        (Uint8List data) => _safeAddOutput(utf8.decode(data, allowMalformed: true)),
        onError: (e) {},
      );

      _safeAddConnection(true);
    } catch (e) {
      _safeAddConnectionError(e);
      rethrow;
    }
  }

  /// Constructs an [SSHClient] on [socket] using [config]'s auth method.
  /// Shared by the target connection and each ProxyJump hop. SSH agent auth
  /// is rejected here because it dials its own socket — direct-connection
  /// agent auth is handled separately in [connect].
  SSHClient _buildClient(SSHSocket socket, SshConnectionConfig config) {
    switch (config.authMethod) {
      case SshAuthMethod.password:
        return SSHClient(
          socket,
          username: config.username,
          onPasswordRequest: () => config.password ?? '',
          onVerifyHostKey: config.onVerifyHostKey,
        );
      case SshAuthMethod.key:
        final keyPair = SSHKeyPair.fromPem(
          config.privateKeyPem!,
          config.passphrase,
        );
        return SSHClient(
          socket,
          username: config.username,
          identities: keyPair,
          onVerifyHostKey: config.onVerifyHostKey,
        );
      case SshAuthMethod.agent:
        throw UnsupportedError(
          'SSH agent auth is only supported for direct connections, '
          'not through a jump host',
        );
    }
  }

  void writeToTerminal(String data) {
    _session?.write(utf8.encode(data));
  }

  void resizeTerminal(int width, int height) {
    _session?.resizeTerminal(width, height);
  }

  void disconnect() {
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    // Tear down forwards before the client — they reference its channels.
    for (final forward in _activeForwards.values) {
      forward.stop();
    }
    _activeForwards.clear();
    _session?.close();
    _client?.close();
    _jumpClient?.close();
    _client = null;
    _jumpClient = null;
    _session = null;
    _safeAddConnection(false);
  }

  void dispose() {
    _disposed = true;
    disconnect();
    if (!_outputController.isClosed) _outputController.close();
    if (!_connectionController.isClosed) _connectionController.close();
  }
}
