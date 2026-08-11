import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../models/known_host.dart';

/// Riverpod provider for [KnownHostsStore]. Override in main() with an
/// initialised instance (mirrors [HostStore]'s pattern).
final knownHostsStoreProvider = Provider<KnownHostsStore>((ref) {
  throw UnimplementedError('Initialize KnownHostsStore in main()');
});

/// Outcome of comparing a presented host key against what we have on file.
enum HostKeyVerification {
  /// Matches a previously-trusted fingerprint.
  trusted,

  /// No record for this host yet — caller should prompt the user.
  unknown,

  /// A record exists but the fingerprint differs — likely MITM.
  mismatch,
}

/// Trust-on-first-use store for SSH host keys, backed by a Hive box.
///
/// Fingerprints are stored as lowercased hex strings. The raw bytes given by
/// dartssh2's `onVerifyHostKey` are converted here so callers don't have to.
class KnownHostsStore {
  static const _boxName = 'known_hosts';

  late Box<KnownHost> _box;

  Future<void> init() async {
    _box = await Hive.openBox<KnownHost>(_boxName);
  }

  /// Compares the presented key against the stored entry (if any).
  Future<HostKeyVerification> verify(
    String host,
    int port,
    String keyType,
    Uint8List fingerprintBytes,
  ) async {
    final fp = _toHex(fingerprintBytes);
    final existing = _box.get(KnownHost(host: host, port: port, keyType: keyType, fingerprint: fp).boxKey);
    if (existing == null) return HostKeyVerification.unknown;
    if (existing.fingerprint.toLowerCase() != fp.toLowerCase() ||
        existing.keyType != keyType) {
      return HostKeyVerification.mismatch;
    }
    return HostKeyVerification.trusted;
  }

  /// Records (or overwrites) the trusted fingerprint for a host.
  Future<void> trust(
    String host,
    int port,
    String keyType,
    Uint8List fingerprintBytes,
  ) async {
    final entry = KnownHost(
      host: host,
      port: port,
      keyType: keyType,
      fingerprint: _toHex(fingerprintBytes),
    );
    await _box.put(entry.boxKey, entry);
  }

  /// Removes the stored entry for a host (e.g. on key rotation).
  Future<void> forget(String host, int port) async {
    await _box.delete('$host:$port');
  }

  static String _toHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString().toLowerCase();
  }
}
