import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/services/secret_cipher.dart';

void main() {
  group('SecretCipher round-trip', () {
    test('encrypt then decrypt returns the original', () {
      final cipher = SecretCipher(passphrase: 'correct horse battery staple');
      const secret = 'p@ssw0rd!';
      final enc = cipher.encrypt(secret);
      expect(enc, isNot(equals(secret)));
      expect(cipher.decrypt(enc), secret);
    });

    test('handles long PEM-like input', () {
      final cipher = SecretCipher(passphrase: 'key');
      final pem = '-----BEGIN PRIVATE KEY-----\n'
          '${List.filled(200, 'AAAA').join()}'
          '\n-----END PRIVATE KEY-----';
      expect(cipher.decrypt(cipher.encrypt(pem)), pem);
    });

    test('empty passphrase passes plaintext through unchanged', () {
      final cipher = SecretCipher(passphrase: '');
      const secret = 'plain';
      expect(cipher.encrypt(secret), secret);
      expect(cipher.decrypt(secret), secret);
    });

    test('two encryptions of the same plaintext differ (random IV)', () {
      final cipher = SecretCipher(passphrase: 'x');
      const secret = 'same';
      final a = cipher.encrypt(secret);
      final b = cipher.encrypt(secret);
      expect(a, isNot(equals(b)));
      // Both still decrypt back to the same value.
      expect(cipher.decrypt(a), secret);
      expect(cipher.decrypt(b), secret);
    });
  });

  group('SecretCipher failure modes', () {
    test('wrong passphrase yields null (not a throw)', () {
      final encrypter = SecretCipher(passphrase: 'right');
      final decrypter = SecretCipher(passphrase: 'wrong');
      final enc = encrypter.encrypt('secret');
      expect(decrypter.decrypt(enc), isNull);
    });

    test('corrupt ciphertext yields null', () {
      final cipher = SecretCipher(passphrase: 'x');
      // Too short to even contain an IV.
      expect(cipher.decrypt('AAAA'), isNull);
      expect(cipher.decrypt('not base64!!!'), isNull);
    });
  });

  group('SecretCipher device salt', () {
    test('same passphrase + explicit salt is deterministic across instances',
        () {
      final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));
      final a = SecretCipher(passphrase: 'p', salt: salt);
      final b = SecretCipher(passphrase: 'p', salt: salt);
      final enc = a.encrypt('hello');
      expect(b.decrypt(enc), 'hello');
    });
  });
}
