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
  });
}
