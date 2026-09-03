import 'dart:async';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'dart:typed_data';

typedef HostKeyVerifier
    = FutureOr<bool> Function(String type, Uint8List fingerprint);

/// Loads default identity keys for "SSH Agent" auth.
///
/// Honest naming note: despite the name, this does NOT talk to an ssh-agent
/// over SSH_AUTH_SOCK/Pageant — dartssh2's `SSHKeyPair.sign` is synchronous,
/// which cannot do the async socket round-trip agent signing requires. Until
/// that changes upstream, "agent" auth here means "load the default identity
/// files from the user's .ssh directory".
class AgentForwardService {
  /// Default private keys to try, in OpenSSH's usual order.
  static const _identityFiles = [
    'id_ed25519',
    'id_ecdsa',
    'id_rsa',
    'id_dsa',
  ];

  /// The user's .ssh directory, honouring both POSIX HOME and the
  /// Windows USERPROFILE (HOME is frequently unset on Windows).
  static Directory? _sshDir() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return null;
    return Directory('$home/.ssh');
  }

  static Future<List<SSHKeyPair>> getAgentKeys() async {
    final keys = <SSHKeyPair>[];

    final sshDir = _sshDir();
    if (sshDir == null || !await sshDir.exists()) return keys;

    for (final name in _identityFiles) {
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
    HostKeyVerifier? onVerifyHostKey,
  }) async {
    final keys = await getAgentKeys();
    if (keys.isEmpty) {
      throw Exception(
        'No usable default identity files found in ~/.ssh '
        '(${_identityFiles.join(', ')}). Encrypted keys need the '
        'password/key auth methods.',
      );
    }

    final socket = await SSHSocket.connect(host, port);
    return SSHClient(
      socket,
      username: username,
      identities: keys,
      onVerifyHostKey: onVerifyHostKey,
    );
  }
}
