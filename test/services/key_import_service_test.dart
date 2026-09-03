import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/services/key_import_service.dart';

void main() {
  // Test-only ed25519 private key (no passphrase, never used anywhere real).
  const testEd25519Pem = '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACCmPTti8vZ1ER1xLSA9ur++u3P+f36/YRcQG2F4rP2Y8AAAAJCWxGMzlsRj
MwAAAAtzc2gtZWQyNTUxOQAAACCmPTti8vZ1ER1xLSA9ur++u3P+f36/YRcQG2F4rP2Y8A
AAAEDywyhZ56ya5ZiDu8Ba7Dq0XnunKH3MiYeSXEpC/yMNEKY9O2Ly9nURHXEtID26v767
c/5/fr9hFxAbYXis/ZjwAAAACXJvb3RAdGVzdAECAwQ=
-----END OPENSSH PRIVATE KEY-----''';

  group('KeyImportService.fromPem', () {
    test('parses ed25519 key and derives public key string', () {
      final key = KeyImportService.fromPem('test_key', testEd25519Pem);

      expect(key.name, 'test_key');
      expect(key.privateKeyPem, testEd25519Pem);
      expect(key.publicKey, isNotEmpty);
      expect(key.publicKey, startsWith('ssh-ed25519 '));
    });

    test('generates a unique id per import', () {
      final a = KeyImportService.fromPem('a', testEd25519Pem);
      final b = KeyImportService.fromPem('b', testEd25519Pem);
      expect(a.id, isNot(b.id));
    });

    test('throws on invalid PEM', () {
      expect(
        () => KeyImportService.fromPem('bad', 'not a key'),
        throwsA(anything),
      );
    });

    test('public key contains a base64 payload', () {
      final key = KeyImportService.fromPem('test_key', testEd25519Pem);
      // Format: "ssh-ed25519 <base64>"
      final parts = key.publicKey.split(' ');
      expect(parts.length, 2);
      // base64 charset only.
      expect(
        RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(parts[1]),
        isTrue,
        reason: 'public key payload should be base64',
      );
    });
  });
}
