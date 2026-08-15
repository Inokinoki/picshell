import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/services/secret_cipher.dart';
import 'package:pointycastle/export.dart' as pc;

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

    test('tampered GCM ciphertext fails authentication and yields null', () {
      final cipher = SecretCipher(passphrase: 'x', salt: Uint8List(16));
      final enc = cipher.encrypt('secret');
      final payload = enc.substring(SecretCipher.v2Marker.length);
      final bytes = base64.decode(payload);
      bytes[bytes.length - 1] ^= 0x01; // flip a tag bit
      final tampered =
          SecretCipher.v2Marker + base64.encode(bytes);
      expect(cipher.decrypt(tampered), isNull);
    });

    test('marker-prefixed ciphertext is null under an empty passphrase',
        () {
      final cipher = SecretCipher(passphrase: 'k', salt: Uint8List(16));
      final enc = cipher.encrypt('secret');
      final plain = SecretCipher(passphrase: '', salt: Uint8List(16));
      expect(plain.decrypt(enc), isNull,
          reason: 'marked value cannot be read without the key');
    });
  });

  group('SecretCipher version markers', () {
    test('encrypt emits the v2 (GCM) marker and is recognised', () {
      final cipher = SecretCipher(passphrase: 'p', salt: Uint8List(16));
      final enc = cipher.encrypt('v');
      expect(enc.startsWith(SecretCipher.v2Marker), isTrue);
      expect(SecretCipher.isEncryptedValue(enc), isTrue);
      expect(cipher.decrypt(enc), 'v');
    });

    test('unmarked legacy (pre-marker CBC) ciphertext still decrypts', () {
      final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));
      const passphrase = 'p';
      // Craft a genuine pre-marker payload: base64(IV||AES-CBC/PK7 ct),
      // key = PBKDF2-HMAC-SHA256(passphrase, salt, 10000, 32).
      final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
        ..init(pc.Pbkdf2Parameters(salt, 10000, 32));
      final key = derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
      final iv = Uint8List.fromList(List<int>.generate(16, (i) => i * 3));
      final cbc = pc.PaddedBlockCipher('AES/CBC/PKCS7')
        ..init(
          true,
          pc.PaddedBlockCipherParameters(
            pc.ParametersWithIV(pc.KeyParameter(key), iv),
            null,
          ),
        );
      final ct = cbc.process(Uint8List.fromList(utf8.encode('legacy-value')));
      final combined = Uint8List(iv.length + ct.length)
        ..setRange(0, iv.length, iv)
        ..setRange(iv.length, iv.length + ct.length, ct);
      final unmarked = base64.encode(combined);

      final cipher = SecretCipher(passphrase: passphrase, salt: salt);
      expect(SecretCipher.isEncryptedValue(unmarked), isFalse);
      expect(cipher.decrypt(unmarked), 'legacy-value',
          reason: 'pre-marker CBC ciphertext stays readable');
    });

    test('unmarked non-ciphertext under a set passphrase returns null',
        () {
      final cipher = SecretCipher(passphrase: 'p', salt: Uint8List(16));
      expect(cipher.decrypt('not ciphertext'), isNull);
    });
  });

  group('SecretCipher salt', () {
    test('same passphrase + explicit salt is deterministic across instances',
        () {
      final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));
      final a = SecretCipher(passphrase: 'p', salt: salt);
      final b = SecretCipher(passphrase: 'p', salt: salt);
      final enc = a.encrypt('hello');
      expect(b.decrypt(enc), 'hello');
    });

    test('default salt is random (two instances disagree)', () {
      final a = SecretCipher(passphrase: 'p');
      final b = SecretCipher(passphrase: 'p');
      final enc = a.encrypt('hello');
      expect(b.decrypt(enc), isNull,
          reason: 'a random default salt must not match across instances');
    });

    test('legacyDeviceSalt is deterministic (16 bytes, stable output)', () {
      final a = SecretCipher.legacyDeviceSalt();
      final b = SecretCipher.legacyDeviceSalt();
      expect(a.length, 16);
      expect(b, equals(a),
          reason: 'migration must re-derive the same legacy salt');
    });
  });
}
