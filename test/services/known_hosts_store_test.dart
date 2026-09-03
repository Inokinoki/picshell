import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:picshell/models/known_host.dart';
import 'package:picshell/services/known_hosts_store.dart';

void main() {
  late KnownHostsStore store;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('picshell_kh_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(KnownHostAdapter());
    }
    store = KnownHostsStore();
    await store.init();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  Uint8List fp(String hex) {
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(out);
  }

  group('KnownHostsStore TOFU', () {
    test('unknown host returns unknown', () async {
      final result = await store.verify(
        '1.2.3.4', 22, 'ssh-ed25519', fp('aabbccdd'),
      );
      expect(result, HostKeyVerification.unknown);
    });

    test('trusted host with matching fingerprint returns trusted', () async {
      await store.trust('1.2.3.4', 22, 'ssh-ed25519', fp('aabbccdd'));
      final result = await store.verify(
        '1.2.3.4', 22, 'ssh-ed25519', fp('aabbccdd'),
      );
      expect(result, HostKeyVerification.trusted);
    });

    test('mismatched fingerprint returns mismatch', () async {
      await store.trust('1.2.3.4', 22, 'ssh-ed25519', fp('aabbccdd'));
      final result = await store.verify(
        '1.2.3.4', 22, 'ssh-ed25519', fp('11223344'),
      );
      expect(result, HostKeyVerification.mismatch);
    });

    test('mismatched key type returns mismatch', () async {
      await store.trust('1.2.3.4', 22, 'ssh-ed25519', fp('aabbccdd'));
      final result = await store.verify(
        '1.2.3.4', 22, 'ssh-rsa', fp('aabbccdd'),
      );
      expect(result, HostKeyVerification.mismatch);
    });

    test('different port is treated as unknown', () async {
      await store.trust('1.2.3.4', 22, 'ssh-ed25519', fp('aabbccdd'));
      final result = await store.verify(
        '1.2.3.4', 2222, 'ssh-ed25519', fp('aabbccdd'),
      );
      expect(result, HostKeyVerification.unknown);
    });

    test('forget removes the entry', () async {
      await store.trust('1.2.3.4', 22, 'ssh-ed25519', fp('aabbccdd'));
      await store.forget('1.2.3.4', 22);
      final result = await store.verify(
        '1.2.3.4', 22, 'ssh-ed25519', fp('aabbccdd'),
      );
      expect(result, HostKeyVerification.unknown);
    });

    test('trust overwrites previous entry', () async {
      await store.trust('1.2.3.4', 22, 'ssh-ed25519', fp('aabbccdd'));
      // Rotate the key.
      await store.trust('1.2.3.4', 22, 'ssh-ed25519', fp('eeff0011'));
      final result = await store.verify(
        '1.2.3.4', 22, 'ssh-ed25519', fp('eeff0011'),
      );
      expect(result, HostKeyVerification.trusted);
    });

    test('dartssh2 2.22 SHA256 ASCII fingerprint round-trips as trusted',
        () async {
      // dartssh2 >= 2.22 passes the OpenSSH-style fingerprint as the UTF-8
      // bytes of "SHA256:<base64>".
      final sha256Ascii = Uint8List.fromList(
        utf8.encode('SHA256:uciU4vSKUXHashCodeExampleValue1234567890ab'),
      );
      await store.trust('1.2.3.4', 22, 'ssh-ed25519', sha256Ascii);
      final result = await store.verify(
        '1.2.3.4', 22, 'ssh-ed25519', sha256Ascii,
      );
      expect(result, HostKeyVerification.trusted);
    });

    test('raw SHA256 digest renders as SHA256:<base64>', () {
      final fpStr = canonicalHostKeyFingerprint(
        Uint8List.fromList(List<int>.generate(32, (i) => i)),
      );
      expect(fpStr, startsWith('SHA256:'));
      expect(fpStr.contains('='), isFalse, reason: 'padding is stripped');
    });

    test('raw MD5 digest renders as colon-separated MD5', () {
      final fpStr = canonicalHostKeyFingerprint(
        Uint8List.fromList(List<int>.generate(16, (i) => i * 3 % 256)),
      );
      expect(fpStr, startsWith('MD5:'));
      expect(fpStr.split(':').length, 17, reason: 'MD5: + 16 byte pairs');
    });

    test('legacy hex-blob record is re-verified, not flagged as MITM',
        () async {
      // Records written before fingerprint normalisation stored the hex of
      // the "SHA256:..." ASCII string. They can never match the canonical
      // form; verify() must treat them as unknown (re-prompt) rather than
      // raising a false MITM mismatch.
      final legacyHex = hexOfAscii('SHA256:uciU4vSKUXHashCode');
      await store.trustFingerprint(
          '1.2.3.4', 22, 'ssh-ed25519', legacyHex);
      final sha256Ascii = Uint8List.fromList(
        utf8.encode('SHA256:uciU4vSKUXHashCode'),
      );
      final result = await store.verify(
        '1.2.3.4', 22, 'ssh-ed25519', sha256Ascii,
      );
      expect(result, HostKeyVerification.unknown,
          reason: 'stale-format records must re-prompt, not mismatch');
    });
  });
}

/// Hex-encodes the UTF-8 bytes of [ascii] — the (buggy) pre-normalisation
/// storage format, kept here to exercise the legacy migration path.
String hexOfAscii(String ascii) {
  return utf8
      .encode(ascii)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}
