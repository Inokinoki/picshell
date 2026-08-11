import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/ssh_key.dart';

/// Imports an SSH private key from the filesystem and derives its OpenSSH
/// public key string. Shared by [ConnectionDialog] (inline import) and
/// [KeyListScreen] (dedicated management UI).
class KeyImportService {
  static const _uuid = Uuid();

  /// Picks a file and parses it into an [SshKey]. Returns null if the user
  /// cancels the picker or the file is not a valid private key.
  static Future<SshKey?> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final path = file.path;
    if (path == null) return null;

    final pem = await File(path).readAsString();
    return fromPem(file.name, pem);
  }

  /// Parses PEM text into an [SshKey], deriving the OpenSSH public key string
  /// from the decoded keypair. Throws if [pem] is not a valid private key.
  static SshKey fromPem(String name, String pem) {
    final keyPairs = SSHKeyPair.fromPem(pem, null);
    final publicKey = keyPairs.isEmpty
        ? ''
        : _toOpenSshPublicKey(keyPairs.first);
    return SshKey(
      id: _uuid.v4(),
      name: name,
      privateKeyPem: pem,
      publicKey: publicKey,
    );
  }

  /// Reconstructs the OpenSSH public key string ("ssh-ed25519 AAAA...") from
  /// a dartssh2 keypair. `toPublicKey().encode()` returns the SSH wire-format
  /// public key (type string + key data), which is exactly what gets base64
  /// encoded in an authorized_keys entry.
  static String _toOpenSshPublicKey(SSHKeyPair keyPair) {
    try {
      final blob = keyPair.toPublicKey().encode();
      return '${keyPair.type} ${base64.encode(blob)}';
    } catch (_) {
      return '';
    }
  }
}
