import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/providers/session_provider.dart';
import 'package:picshell/services/known_hosts_store.dart';
import 'package:picshell/services/ssh_service.dart';

/// Shared across transports so a failure budget applies to connect ATTEMPTS
/// (each reconnect creates a fresh transport, which must not reset the
/// budget).
class FailureBudget {
  int remaining;
  FailureBudget(this.remaining);
}

/// Scriptable transport: records calls so tests can assert the session
/// lifecycle actually reconnected, rebound I/O, and backed off. connect()
/// invokes the config's host-key verifier the way dartssh2 does and fails
/// when it returns false.
class FakeSshTransport implements SshTransport {
  final FailureBudget? budget;
  final _output = StreamController<String>.broadcast();
  final _connection = StreamController<bool>.broadcast();

  int connectCalls = 0;
  final List<String> written = [];
  int disposeCalls = 0;

  FakeSshTransport({this.budget});

  @override
  Future<void> connect(SshConnectionConfig config) async {
    connectCalls++;
    final verify = config.onVerifyHostKey;
    if (verify != null) {
      final fingerprint =
          Uint8List.fromList(List.generate(32, (i) => i + 1));
      final accepted = await verify('ssh-ed25519', fingerprint);
      if (!accepted) {
        // dartssh2 closes the transport here and surfaces a generic
        // SSHAuthAbortError; the typed reason is our business.
        _connection.add(false);
        throw Exception('host key rejected by verifier');
      }
    }
    final b = budget;
    if (b != null && b.remaining > 0) {
      b.remaining--;
      _connection.add(false);
      throw Exception('connect failed (attempt $connectCalls)');
    }
    _connection.add(true);
  }

  @override
  void writeToTerminal(String data) => written.add(data);

  @override
  void resizeTerminal(int width, int height) {}

  @override
  void dispose() {
    disposeCalls++;
  }

  @override
  Stream<String> get output => _output.stream;

  @override
  Stream<bool> get connectionState => _connection.stream;

  @override
  bool get isConnected => true;

  void simulateDisconnect() => _connection.add(false);
}

class _TrustingKnownHosts implements KnownHostsStore {
  @override
  Future<void> init() async {}

  @override
  Future<HostKeyVerification> verify(
    String host,
    int port,
    String keyType,
    Uint8List fingerprintBytes,
  ) async =>
      HostKeyVerification.trusted;

  @override
  Future<void> trust(
    String host,
    int port,
    String keyType,
    Uint8List fingerprintBytes,
  ) async {}

  @override
  Future<void> forget(String host, int port) async {}
}

class _FixedKnownHosts implements KnownHostsStore {
  final HostKeyVerification result;
  _FixedKnownHosts(this.result);

  @override
  Future<void> init() async {}

  @override
  Future<HostKeyVerification> verify(
    String host,
    int port,
    String keyType,
    Uint8List fingerprintBytes,
  ) async =>
      result;

  @override
  Future<void> trust(
    String host,
    int port,
    String keyType,
    Uint8List fingerprintBytes,
  ) async {}

  @override
  Future<void> forget(String host, int port) async {}
}

void main() {
  group('Session lifecycle (real reconnect behaviour)', () {
    final created = <FakeSshTransport>[];
    final budget = FailureBudget(0);
    late ProviderContainer container;
    late Host testHost;
    late SshConnectionConfig testConfig;

    ProviderContainer buildContainer() => ProviderContainer(overrides: [
          knownHostsStoreProvider.overrideWithValue(_TrustingKnownHosts()),
          sessionListProvider.overrideWith((ref) => SessionListNotifier(
                ref,
                transportFactory: () {
                  final fake = FakeSshTransport(budget: budget);
                  created.add(fake);
                  return fake;
                },
              )),
        ]);

    setUp(() {
      created.clear();
      budget.remaining = 0;
      container = buildContainer();
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

    test('config is preserved after the first successful connect', () async {
      // Regression: the post-connect state rebuild used to drop config,
      // which silently disabled auto-reconnect forever.
      await container
          .read(sessionListProvider.notifier)
          .openSession(testHost, testConfig);

      final session = container.read(sessionListProvider).single;
      expect(session.connected, true);
      expect(session.config, isNotNull);
      expect(session.config!.host, '192.0.2.1');
      expect(created.single.connectCalls, 1);
    });

    test('transport disconnect triggers reconnect with a new transport',
        () async {
      await container
          .read(sessionListProvider.notifier)
          .openSession(testHost, testConfig);

      created.first.simulateDisconnect();

      // First backoff is 1s.
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      final session = container.read(sessionListProvider).single;
      expect(session.connected, true, reason: 'reconnect should succeed');
      expect(session.reconnecting, false);
      expect(created, hasLength(2));
      expect(created[1].connectCalls, 1);
      expect(identical(session.sshService, created[1]), isTrue);
    });

    test('terminal input follows the new transport after reconnect',
        () async {
      await container
          .read(sessionListProvider.notifier)
          .openSession(testHost, testConfig);

      created.first.simulateDisconnect();
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      final session = container.read(sessionListProvider).single;
      // Regression: the terminal callbacks used to capture the FIRST
      // service, so keystrokes went to the disposed transport.
      session.terminal.onOutput!('ls\n');
      expect(created[1].written, contains('ls\n'));
    });

    test('failed reconnects back off and eventually succeed', () async {
      await container
          .read(sessionListProvider.notifier)
          .openSession(testHost, testConfig);
      // Only the reconnect attempts should fail.
      budget.remaining = 2;
      created.first.simulateDisconnect();

      // 1s + 2s + 4s of backoff, plus slack.
      await Future<void>.delayed(const Duration(seconds: 9));

      expect(container.read(sessionListProvider).single.connected, true);
      // Initial transport + three reconnect transports (2 failures then 1
      // success).
      expect(created, hasLength(4));
      expect(budget.remaining, 0);
    });

    test('manual close does not trigger a reconnect', () async {
      await container
          .read(sessionListProvider.notifier)
          .openSession(testHost, testConfig);

      created.first.simulateDisconnect();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      container
          .read(sessionListProvider.notifier)
          .closeSession(container.read(sessionListProvider).single.id);

      await Future<void>.delayed(const Duration(seconds: 2));
      expect(container.read(sessionListProvider), isEmpty);
      expect(created, hasLength(1));
    });

    test('unknown host key surfaces UnknownHostException, not a generic error',
        () async {
      // Regression: dartssh2 swallows exceptions thrown inside
      // onVerifyHostKey and fails the connect with a generic
      // "connection closed before authentication". The session must
      // translate the recorded rejection back into the typed exception the
      // TOFU dialog flow catches.
      final container = ProviderContainer(overrides: [
        knownHostsStoreProvider
            .overrideWithValue(_FixedKnownHosts(HostKeyVerification.unknown)),
        sessionListProvider.overrideWith((ref) => SessionListNotifier(
              ref,
              transportFactory: () {
                final fake = FakeSshTransport();
                created.add(fake);
                return fake;
              },
            )),
      ]);
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(sessionListProvider.notifier)
            .openSession(testHost, testConfig),
        throwsA(isA<UnknownHostException>()),
      );
      expect(container.read(sessionListProvider), isEmpty);
    });

    test('mismatched host key surfaces HostKeyMismatchException', () async {
      final container = ProviderContainer(overrides: [
        knownHostsStoreProvider
            .overrideWithValue(_FixedKnownHosts(HostKeyVerification.mismatch)),
        sessionListProvider.overrideWith((ref) => SessionListNotifier(
              ref,
              transportFactory: () {
                final fake = FakeSshTransport();
                created.add(fake);
                return fake;
              },
            )),
      ]);
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(sessionListProvider.notifier)
            .openSession(testHost, testConfig),
        throwsA(isA<HostKeyMismatchException>()),
      );
    });
  });
}
