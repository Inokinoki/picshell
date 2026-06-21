import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/providers/session_provider.dart';
import 'package:picshell/services/ssh_service.dart';

void main() {
  group('SSH connection config', () {
    test('password auth config has all fields', () {
      final config = SshConnectionConfig(
        host: 'example.com',
        port: 22,
        username: 'user',
        authMethod: SshAuthMethod.password,
        password: 'pass123',
      );

      expect(config.host, 'example.com');
      expect(config.port, 22);
      expect(config.username, 'user');
      expect(config.authMethod, SshAuthMethod.password);
      expect(config.password, 'pass123');
      expect(config.privateKeyPem, isNull);
      expect(config.passphrase, isNull);
    });

    test('key auth config has all fields', () {
      const pem = '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----';
      final config = SshConnectionConfig(
        host: 'example.com',
        port: 2222,
        username: 'admin',
        authMethod: SshAuthMethod.key,
        privateKeyPem: pem,
        passphrase: 'secret',
      );

      expect(config.authMethod, SshAuthMethod.key);
      expect(config.privateKeyPem, pem);
      expect(config.passphrase, 'secret');
    });

    test('default port is 22', () {
      final config = SshConnectionConfig(
        host: 'h',
        username: 'u',
        authMethod: SshAuthMethod.password,
        password: 'p',
      );
      expect(config.port, 22);
    });
  });

  group('SSH connection failure handling', () {
    test('connect to unreachable host throws', () async {
      final service = SshService();
      final config = SshConnectionConfig(
        host: '192.0.2.1',
        port: 22,
        username: 'test',
        authMethod: SshAuthMethod.password,
        password: 'test',
      );

      expect(
        service.connect(config).timeout(const Duration(seconds: 10)),
        throwsA(anything),
      );

      await Future.delayed(const Duration(seconds: 11));
      service.dispose();
    });

    test('connect to closed port throws', () async {
      final service = SshService();
      final config = SshConnectionConfig(
        host: '127.0.0.1',
        port: 1,
        username: 'test',
        authMethod: SshAuthMethod.password,
        password: 'test',
      );

      expect(
        service.connect(config).timeout(const Duration(seconds: 5)),
        throwsA(anything),
      );

      await Future.delayed(const Duration(seconds: 6));
      service.dispose();
    });

    test('connection failure does not crash service', () async {
      final service = SshService();
      final config = SshConnectionConfig(
        host: '127.0.0.1',
        port: 1,
        username: 'test',
        authMethod: SshAuthMethod.password,
        password: 'test',
      );

      try {
        await service.connect(config).timeout(const Duration(seconds: 5));
        fail('Should have thrown');
      } catch (e) {
        expect(e, isNotNull);
      }

      expect(service.isConnected, false);
      expect(() => service.dispose(), returnsNormally);
    });

    test('writeToTerminal after failed connection does not throw', () async {
      final service = SshService();
      final config = SshConnectionConfig(
        host: '127.0.0.1',
        port: 1,
        username: 'test',
        authMethod: SshAuthMethod.password,
        password: 'test',
      );

      try {
        await service.connect(config).timeout(const Duration(seconds: 5));
      } catch (_) {}

      expect(() => service.writeToTerminal('test'), returnsNormally);
      expect(() => service.resizeTerminal(80, 24), returnsNormally);

      service.dispose();
    });

    test('multiple failed connect attempts do not corrupt state', () async {
      final service = SshService();
      final config = SshConnectionConfig(
        host: '127.0.0.1',
        port: 1,
        username: 'test',
        authMethod: SshAuthMethod.password,
        password: 'test',
      );

      for (int i = 0; i < 3; i++) {
        try {
          await service.connect(config).timeout(const Duration(seconds: 2));
        } catch (_) {}
      }

      expect(service.isConnected, false);
      service.dispose();
    });

    test('dispose during pending connection does not crash', () async {
      final service = SshService();
      final config = SshConnectionConfig(
        host: '192.0.2.1',
        port: 22,
        username: 'test',
        authMethod: SshAuthMethod.password,
        password: 'test',
      );

      final connectFuture = service.connect(config).timeout(const Duration(seconds: 10));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(() => service.dispose(), returnsNormally);

      try {
        await connectFuture;
      } catch (_) {}
    });
  });

  group('Session provider integration', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('session provider handles connection failure gracefully', () async {
      final notifier = container.read(sessionListProvider.notifier);

      final host = Host(
        id: 'test-1',
        name: 'Test',
        hostname: '127.0.0.1',
        port: 1,
        username: 'test',
        authType: AuthType.password,
        password: 'test',
      );

      final config = SshConnectionConfig(
        host: '127.0.0.1',
        port: 1,
        username: 'test',
        authMethod: SshAuthMethod.password,
        password: 'test',
      );

      await runZonedGuarded(() async {
        try {
          await notifier.openSession(host, config).timeout(const Duration(seconds: 5));
        } catch (_) {}
      }, (e, s) {});

      await Future.delayed(const Duration(milliseconds: 500));

      expect(container.read(sessionListProvider), isEmpty);
    });

    test('debugAddSession adds session to state', () {
      final notifier = container.read(sessionListProvider.notifier);

      final host = Host(
        id: 'h1',
        name: 'Test',
        hostname: '127.0.0.1',
        port: 22,
        username: 'user',
        authType: AuthType.password,
        password: 'pass',
      );

      final session = SessionState(
        id: 's1',
        host: host,
        sshService: SshService(),
        config: SshConnectionConfig(
          host: '127.0.0.1',
          port: 22,
          username: 'user',
          authMethod: SshAuthMethod.password,
          password: 'pass',
        ),
      );

      notifier.debugAddSession(session);
      expect(container.read(sessionListProvider).length, 1);
      expect(container.read(sessionListProvider).first.id, 's1');
    });

    test('closeSession removes session', () {
      final notifier = container.read(sessionListProvider.notifier);

      final host = Host(
        id: 'h1',
        name: 'Test',
        hostname: '127.0.0.1',
        port: 22,
        username: 'user',
        authType: AuthType.password,
        password: 'pass',
      );

      final session = SessionState(
        id: 's1',
        host: host,
        sshService: SshService(),
        config: SshConnectionConfig(
          host: '127.0.0.1',
          port: 22,
          username: 'user',
          authMethod: SshAuthMethod.password,
          password: 'pass',
        ),
      );

      notifier.debugAddSession(session);
      expect(container.read(sessionListProvider).length, 1);

      notifier.closeSession('s1');
      expect(container.read(sessionListProvider), isEmpty);
    });

    test('reconnect does not trigger on manual close', () async {
      final notifier = container.read(sessionListProvider.notifier);

      final host = Host(
        id: 'h1',
        name: 'Test',
        hostname: '127.0.0.1',
        port: 22,
        username: 'user',
        authType: AuthType.password,
        password: 'pass',
      );

      final session = SessionState(
        id: 's1',
        host: host,
        sshService: SshService(),
        config: SshConnectionConfig(
          host: '127.0.0.1',
          port: 22,
          username: 'user',
          authMethod: SshAuthMethod.password,
          password: 'pass',
        ),
      );

      notifier.debugAddSession(session);
      notifier.closeSession('s1');

      await Future.delayed(const Duration(seconds: 1));
      expect(container.read(sessionListProvider), isEmpty);
    });

    test('SessionState preserves config for reconnect', () {
      final config = SshConnectionConfig(
        host: '10.0.0.1',
        port: 2222,
        username: 'admin',
        authMethod: SshAuthMethod.password,
        password: 'secret',
      );

      final host = Host(
        id: 'h1',
        name: 'Server',
        hostname: '10.0.0.1',
        port: 2222,
        username: 'admin',
        authType: AuthType.password,
        password: 'secret',
      );

      final session = SessionState(
        id: 's1',
        host: host,
        sshService: SshService(),
        config: config,
      );

      expect(session.config, isNotNull);
      expect(session.config!.host, '10.0.0.1');
      expect(session.config!.port, 2222);
      expect(session.connected, false);
      expect(session.reconnecting, false);
    });

    test('SessionState reconnecting flag transitions correctly', () {
      final host = Host(
        id: 'h1',
        name: 'Test',
        hostname: '127.0.0.1',
        port: 22,
        username: 'user',
        authType: AuthType.password,
        password: 'pass',
      );

      final normal = SessionState(
        id: 's1',
        host: host,
        sshService: SshService(),
        config: SshConnectionConfig(
          host: '127.0.0.1',
          port: 22,
          username: 'user',
          authMethod: SshAuthMethod.password,
          password: 'pass',
        ),
      );
      expect(normal.reconnecting, false);

      final reconnecting = SessionState(
        id: normal.id,
        host: normal.host,
        sshService: normal.sshService,
        terminal: normal.terminal,
        connected: false,
        reconnecting: true,
        config: normal.config,
      );
      expect(reconnecting.reconnecting, true);
      expect(reconnecting.connected, false);

      final restored = SessionState(
        id: normal.id,
        host: normal.host,
        sshService: normal.sshService,
        terminal: normal.terminal,
        connected: true,
        reconnecting: false,
        config: normal.config,
      );
      expect(restored.reconnecting, false);
      expect(restored.connected, true);
    });
  });
}
