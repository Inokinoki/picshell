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

  Stream<String> get output => _outputController.stream;
  Stream<bool> get connectionState => _connectionController.stream;
  bool get isConnected => _client != null && _session != null;

  Future<void> connect(SshConnectionConfig config) async {
    try {
      _connectionController.add(false);

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

      _session!.stdout.listen(
        (Uint8List data) => _outputController.add(utf8.decode(data)),
      );

      _session!.stderr.listen(
        (Uint8List data) => _outputController.add(utf8.decode(data)),
      );

      _connectionController.add(true);
    } catch (e) {
      _connectionController.addError(e);
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
    _session?.close();
    _client?.close();
    _client = null;
    _session = null;
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _outputController.close();
    _connectionController.close();
  }
}
