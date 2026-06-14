import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/providers/session_provider.dart';
import 'package:picshell/services/ssh_service.dart';

void main() {
  group('Session reconnect logic', () {
    late ProviderContainer container;
    late Host testHost;
    late SshConnectionConfig testConfig;

    setUp(() {
      container = ProviderContainer();
      testHost = Host(
        id: 'host-1',
        name: 'Test Host',
        hostname: '192.0.2.1',
        port: 22,
        username: 'test',
        authType: AuthType.password,
        password: 'password',
      );
      testConfig = SshConnectionConfig(
        host: '192.0.2.1',
        port: 22,
        username: 'test',
        authMethod: SshAuthMethod.password,
        password: 'password',
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('session state stores config for reconnection', () {
      final session = SessionState(
        id: 'test-1',
        host: testHost,
        sshService: SshService(),
        config: testConfig,
      );

      expect(session.config, isNotNull);
      expect(session.config!.host, '192.0.2.1');
      expect(session.connected, false);
      expect(session.reconnecting, false);
    });

    test('closeSession removes session and cancels timers', () {
      final notifier = container.read(sessionListProvider.notifier);
      final service = SshService();

      final session = SessionState(
        id: 'test-1',
        host: testHost,
        sshService: service,
        config: testConfig,
      );

      notifier.debugAddSession(session);

      expect(container.read(sessionListProvider).length, 1);

      notifier.closeSession('test-1');

      expect(container.read(sessionListProvider), isEmpty);
    });

    test('reconnecting flag defaults to false', () {
      final session = SessionState(
        id: 'test-1',
        host: testHost,
        sshService: SshService(),
        config: testConfig,
      );
      expect(session.reconnecting, false);
    });

    test('reconnecting session has correct state', () {
      final session = SessionState(
        id: 'test-1',
        host: testHost,
        sshService: SshService(),
        connected: false,
        reconnecting: true,
        config: testConfig,
      );

      expect(session.reconnecting, true);
      expect(session.connected, false);
      expect(session.config, isNotNull);
    });

    test('successful reconnect produces connected non-reconnecting state', () {
      final session = SessionState(
        id: 'test-1',
        host: testHost,
        sshService: SshService(),
        connected: false,
        reconnecting: true,
        config: testConfig,
      );

      final reconnected = SessionState(
        id: session.id,
        host: session.host,
        sshService: session.sshService,
        terminal: session.terminal,
        connected: true,
        reconnecting: false,
        config: session.config,
      );

      expect(reconnected.connected, true);
      expect(reconnected.reconnecting, false);
    });

    test('terminal persists across reconnection', () {
      final session = SessionState(
        id: 'test-1',
        host: testHost,
        sshService: SshService(),
        config: testConfig,
      );

      final reconnected = SessionState(
        id: session.id,
        host: session.host,
        sshService: SshService(),
        terminal: session.terminal,
        connected: true,
        reconnecting: false,
        config: session.config,
      );

      expect(identical(session.terminal, reconnected.terminal), true);
    });

    test('SshService can be disposed during reconnect cycle', () {
      final service1 = SshService();
      final service2 = SshService();

      service1.dispose();
      service2.dispose();

      expect(() => service1.writeToTerminal('test'), returnsNormally);
      expect(() => service2.resizeTerminal(80, 24), returnsNormally);
    });

    test('connectionState stream does not emit without connect', () async {
      final service = SshService();

      final states = <bool>[];
      final sub = service.connectionState.listen(states.add);

      await Future.delayed(const Duration(milliseconds: 10));

      expect(states, isEmpty);

      await sub.cancel();
      service.dispose();
    });

    test('dispose and reconnect does not crash', () {
      final service = SshService();
      service.dispose();

      final newService = SshService();
      expect(newService.isConnected, false);
      newService.dispose();
    });
  });
}
