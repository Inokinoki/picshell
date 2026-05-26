import 'dart:io';
import 'package:dartssh2/dartssh2.dart';

class AgentForwardService {
  static Future<List<SSHKeyPair>> getAgentKeys() async {
    final keys = <SSHKeyPair>[];

    // Try to read keys from default SSH directory
    final sshDir = Directory('${Platform.environment['HOME']}/.ssh');
    if (!await sshDir.exists()) return keys;

    final keyFiles = ['id_rsa', 'id_ecdsa', 'id_ed25519', 'id_dsa'];

    for (final name in keyFiles) {
      final file = File('${sshDir.path}/$name');
      if (await file.exists()) {
        try {
          final pem = await file.readAsString();
          final keyPairs = SSHKeyPair.fromPem(pem, null);
          keys.addAll(keyPairs);
        } catch (_) {
          // Skip invalid or encrypted keys without passphrase
        }
      }
    }

    return keys;
  }

  static Future<SSHClient?> connectWithAgent({
    required String host,
    required int port,
    required String username,
  }) async {
    final keys = await getAgentKeys();

    final socket = await SSHSocket.connect(host, port);
    return SSHClient(socket, username: username, identities: keys);
  }
}
