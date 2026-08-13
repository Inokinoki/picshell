import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/services/vault_service.dart';

/// In-memory VaultBackend for exercising VaultService without device plugins.
class _FakeBackend implements VaultBackend {
  String? storedKey;
  bool canCheck = true;
  bool authResult = true;

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<bool> authenticate({String reason = ''}) async => authResult;

  @override
  Future<String?> readKey() async => storedKey;

  @override
  Future<void> writeKey(String key) async => storedKey = key;

  @override
  Future<void> deleteKey() async => storedKey = null;
}

void main() {
  group('VaultService', () {
    test('getMasterKey generates and persists a 32-byte passphrase on first use',
        () async {
      final backend = _FakeBackend();
      final vault = VaultService(backend);

      expect(await vault.isEnrolled, isFalse);
      final key = await vault.getMasterKey();

      // Decodes to exactly 32 random bytes.
      final bytes = base64Url.decode(key);
      expect(bytes.length, 32);
      // Persisted to the backend.
      expect(backend.storedKey, key);
      expect(await vault.isEnrolled, isTrue);
    });

    test('getMasterKey is idempotent — same key returned forever', () async {
      final backend = _FakeBackend();
      final vault = VaultService(backend);

      final first = await vault.getMasterKey();
      final second = await vault.getMasterKey();
      final third = await vault.getMasterKey();

      expect(second, first);
      expect(third, first);
    });

    test('two fresh vaults produce distinct keys', () async {
      final a = await VaultService(_FakeBackend()).getMasterKey();
      final b = await VaultService(_FakeBackend()).getMasterKey();
      expect(a, isNot(b));
    });

    test('canAuthenticate and authenticate delegate to the backend', () async {
      final backend = _FakeBackend()..canCheck = false..authResult = false;
      final vault = VaultService(backend);

      expect(await vault.canAuthenticate, isFalse);
      expect(await vault.authenticate(), isFalse);

      backend.canCheck = true;
      backend.authResult = true;
      expect(await vault.canAuthenticate, isTrue);
      expect(await vault.authenticate(), isTrue);
    });

    test('unenroll clears the persisted key', () async {
      final backend = _FakeBackend();
      final vault = VaultService(backend);
      await vault.getMasterKey();
      expect(await vault.isEnrolled, isTrue);

      await vault.unenroll();
      expect(await vault.isEnrolled, isFalse);
      expect(backend.storedKey, isNull);
    });
  });
}
