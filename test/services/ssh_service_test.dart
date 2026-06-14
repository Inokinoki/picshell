import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/services/ssh_service.dart';

void main() {
  group('SshService', () {
    test('connection config can be created', () {
      final config = SshConnectionConfig(
        host: '192.168.1.1',
        username: 'root',
        authMethod: SshAuthMethod.password,
        password: 'test',
      );
      expect(config.host, '192.168.1.1');
      expect(config.port, 22);
      expect(config.authMethod, SshAuthMethod.password);
    });

    test('SshService initial state', () {
      final service = SshService();
      expect(service.isConnected, false);
    });

    test('dispose closes streams without throwing', () {
      final service = SshService();
      expect(() => service.dispose(), returnsNormally);
    });

    test('dispose is idempotent', () {
      final service = SshService();
      service.dispose();
      expect(() => service.dispose(), returnsNormally);
    });

    test('output stream is listenable before dispose', () async {
      final service = SshService();
      final received = <String>[];
      final sub = service.output.listen(received.add);
      await sub.cancel();
      service.dispose();
    });

    test('connectionState stream is listenable before dispose', () async {
      final service = SshService();
      final received = <bool>[];
      final sub = service.connectionState.listen(received.add);
      await sub.cancel();
      service.dispose();
    });

    test('disconnect after dispose does not throw', () {
      final service = SshService();
      service.dispose();
      expect(() => service.disconnect(), returnsNormally);
    });

    test('writeToTerminal on disposed service does not throw', () {
      final service = SshService();
      service.dispose();
      expect(() => service.writeToTerminal('test'), returnsNormally);
    });

    test('resizeTerminal on disposed service does not throw', () {
      final service = SshService();
      service.dispose();
      expect(() => service.resizeTerminal(80, 24), returnsNormally);
    });

    test('multiple listeners on broadcast connectionState', () async {
      final service = SshService();
      final l1 = <bool>[];
      final l2 = <bool>[];
      final s1 = service.connectionState.listen(l1.add);
      final s2 = service.connectionState.listen(l2.add);

      await s1.cancel();
      await s2.cancel();
      service.dispose();
    });

    test('connect to invalid host fails gracefully', () async {
      final service = SshService();
      final config = SshConnectionConfig(
        host: '192.0.2.1',
        port: 22,
        username: 'test',
        authMethod: SshAuthMethod.password,
        password: 'test',
      );

      await expectLater(
        service.connect(config).timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw Exception('timeout'),
            ),
        throwsA(anything),
      );

      service.dispose();
    });
  });

  group('SshService connection config', () {
    test('password auth config', () {
      final config = SshConnectionConfig(
        host: 'localhost',
        username: 'user',
        authMethod: SshAuthMethod.password,
        password: 'pass',
      );
      expect(config.authMethod, SshAuthMethod.password);
      expect(config.password, 'pass');
      expect(config.privateKeyPem, isNull);
    });

    test('key auth config', () {
      final config = SshConnectionConfig(
        host: 'localhost',
        username: 'user',
        authMethod: SshAuthMethod.key,
        privateKeyPem: '-----BEGIN PRIVATE KEY-----',
        passphrase: 'secret',
      );
      expect(config.authMethod, SshAuthMethod.key);
      expect(config.privateKeyPem, '-----BEGIN PRIVATE KEY-----');
      expect(config.passphrase, 'secret');
    });

    test('agent auth config', () {
      final config = SshConnectionConfig(
        host: 'localhost',
        username: 'user',
        authMethod: SshAuthMethod.agent,
      );
      expect(config.authMethod, SshAuthMethod.agent);
    });

    test('custom port', () {
      final config = SshConnectionConfig(
        host: 'localhost',
        port: 2222,
        username: 'user',
        authMethod: SshAuthMethod.password,
        password: 'pass',
      );
      expect(config.port, 2222);
    });
  });
}

