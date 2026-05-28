import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'agent_forward_service.dart';

enum SshAuthMethod { password, key, agent }

class SshConnectionConfig {
  final String host;
  final int port;
  final String username;
  final SshAuthMethod authMethod;
  final String? password;
  final String? privateKeyPem;
  final String? passphrase;

  SshConnectionConfig({
    required this.host,
    this.port = 22,
    required this.username,
    required this.authMethod,
    this.password,
    this.privateKeyPem,
    this.passphrase,
  });
}

class SshService {
  SSHClient? _client;
  SSHSession? _session;
  final StreamController<String> _outputController =
      StreamController.broadcast();
  final StreamController<bool> _connectionController =
      StreamController.broadcast();
  StreamSubscription<Uint8List>? _stdoutSubscription;
  StreamSubscription<Uint8List>? _stderrSubscription;
  bool _disposed = false;

  Stream<String> get output => _outputController.stream;
  Stream<bool> get connectionState => _connectionController.stream;
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

  void _safeAddConnectionError(Object e) {
    if (!_disposed && !_connectionController.isClosed) {
      _connectionController.addError(e);
    }
  }

  Future<void> connect(SshConnectionConfig config) async {
    try {
      _safeAddConnection(false);

      final socket = await SSHSocket.connect(config.host, config.port);

      SSHClient client;
      switch (config.authMethod) {
        case SshAuthMethod.password:
          client = SSHClient(
            socket,
            username: config.username,
            onPasswordRequest: () => config.password ?? '',
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
          );
          break;
        case SshAuthMethod.agent:
          final agentClient = await AgentForwardService.connectWithAgent(
            host: config.host,
            port: config.port,
            username: config.username,
          );
          if (agentClient != null) {
            client = agentClient;
          } else {
            throw Exception('No SSH keys found in ~/.ssh/');
          }
          break;
      }

      _client = client;
      _session = await client.shell(
        pty: const SSHPtyConfig(width: 80, height: 24, type: 'xterm-256color'),
      );

      _stdoutSubscription = _session!.stdout.listen(
        (Uint8List data) => _safeAddOutput(utf8.decode(data)),
        onError: (e) {
          _safeAddConnection(false);
        },
        onDone: () {
          _safeAddConnection(false);
        },
      );

      _stderrSubscription = _session!.stderr.listen(
        (Uint8List data) => _safeAddOutput(utf8.decode(data)),
        onError: (e) {},
      );

      _safeAddConnection(true);
    } catch (e) {
      _safeAddConnectionError(e);
      rethrow;
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
    _session?.close();
    _client?.close();
    _client = null;
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
