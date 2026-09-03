import 'dart:convert';
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

/// Canonical, human-comparable form of a host-key fingerprint.
///
/// dartssh2 >= 2.22 hands `onVerifyHostKey` the OpenSSH-style fingerprint as
/// the UTF-8 bytes of `"SHA256:<base64>"`; older versions handed the raw MD5
/// digest bytes. Hexing either blindly produces garbage on screen (the
/// SHA256 variant shows as the hex of the ASCII string itself). Normalise
/// everything into the forms `ssh-keygen -l` prints:
///
///  * `SHA256:<base64, no padding>` for SHA-256 digests,
///  * `MD5:aa:bb:...` for MD5 digests,
///  * plain hex as a last-resort fallback for anything unrecognisable.
String canonicalHostKeyFingerprint(Uint8List bytes) {
  final asText = utf8.decode(bytes, allowMalformed: true);
  final tagged = RegExp(r'^(SHA256|MD5):([A-Za-z0-9+/=]{16,}|[0-9a-fA-F:]{16,})')
      .firstMatch(asText);
  if (tagged != null) {
    final algo = tagged.group(1)!;
    final value = tagged.group(2)!;
    if (algo == 'MD5') {
      return 'MD5:${_colonHex(_hexToBytes(value.replaceAll(':', '')))}';
    }
    return 'SHA256:${value.replaceAll('=', '')}';
  }
  // Legacy dartssh2 (< 2.22) passed the raw digest bytes.
  if (bytes.length == 16) return 'MD5:${_colonHex(bytes)}';
  if (bytes.length == 32) {
    return 'SHA256:${base64.encode(bytes).replaceAll('=', '')}';
  }
  return _colonHex(bytes);
}

/// True when [fingerprint] is in the canonical form produced by
/// [canonicalHostKeyFingerprint]. Entries stored before the fingerprint
/// format was normalised are hex-of-ASCII blobs (one long colonless hex
/// run); treating them as unknown (re-prompt) is safer than a false MITM
/// mismatch.
bool isCanonicalHostKeyFingerprint(String fingerprint) {
  final f = fingerprint.toLowerCase();
  if (f.startsWith('sha256:')) return !f.substring(7).contains(':');
  if (f.startsWith('md5:')) {
    return RegExp(r'^md5:([0-9a-f]{2}:)*[0-9a-f]{2}$').hasMatch(f);
  }
  // Bare fallback form: colon-separated hex pairs.
  return RegExp(r'^[0-9a-f]{2}(:[0-9a-f]{2})*$').hasMatch(f);
}

String _colonHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
}

Uint8List _hexToBytes(String hex) {
  final out = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(out);
}

/// Trust-on-first-use store for SSH host keys, backed by a Hive box.
///
/// Fingerprints are stored in the canonical form returned by
/// [canonicalHostKeyFingerprint], so what the user is asked to compare is
/// exactly what is remembered.
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
    final fp = canonicalHostKeyFingerprint(fingerprintBytes);
    final existing = _box.get(KnownHost(host: host, port: port, keyType: keyType, fingerprint: fp).boxKey);
    if (existing == null) return HostKeyVerification.unknown;
    // Pre-normalisation records stored hex-of-ASCII blobs; re-verify them
    // instead of raising a false MITM mismatch.
    if (!isCanonicalHostKeyFingerprint(existing.fingerprint)) {
      return HostKeyVerification.unknown;
    }
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
    await trustFingerprint(
      host,
      port,
      keyType,
      canonicalHostKeyFingerprint(fingerprintBytes),
    );
  }

  /// Records a fingerprint that is already in canonical form — the path used
  /// after the TOFU dialog, where the string has already been normalised for
  /// display and no raw bytes are available any more.
  Future<void> trustFingerprint(
    String host,
    int port,
    String keyType,
    String fingerprint,
  ) async {
    final entry = KnownHost(
      host: host,
      port: port,
      keyType: keyType,
      fingerprint: fingerprint,
    );
    await _box.put(entry.boxKey, entry);
  }

  /// Removes the stored entry for a host (e.g. on key rotation).
  Future<void> forget(String host, int port) async {
    await _box.delete('$host:$port');
  }
}
