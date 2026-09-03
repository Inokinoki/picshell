import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:picshell/app/app.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/forward_rule.dart';
import 'package:picshell/models/known_host.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/providers/host_provider.dart';
import 'package:picshell/providers/session_provider.dart';
import 'package:picshell/providers/settings_provider.dart';
import 'package:picshell/providers/vault_provider.dart';
import 'package:picshell/screens/home/home_screen.dart'
    show selectedSessionIndexProvider;
import 'package:picshell/services/host_store.dart';
import 'package:picshell/services/known_hosts_store.dart';
import 'package:picshell/services/ssh_service.dart';
import 'package:picshell/services/vault_service.dart';

/// Connection target for the throwaway docker sshd (Dockerfile.sshd).
const sshHost = String.fromEnvironment('TEST_SSH_HOST', defaultValue: '127.0.0.1');
const sshPort = int.fromEnvironment('TEST_SSH_PORT', defaultValue: 2222);
const sshUser = String.fromEnvironment('TEST_SSH_USER', defaultValue: 'root');
const sshPass = String.fromEnvironment('TEST_SSH_PASS', defaultValue: 'testpass');

/// Switchable vault backend: [grant] controls whether authenticate()
/// succeeds, so the unlock success and failure paths are both testable
/// without platform biometrics.
class SwitchableBackend implements VaultBackend {
  bool grant = false;
  String? storedKey;

  @override
  Future<bool> get canCheckBiometrics async => true;
  @override
  Future<bool> authenticate({String reason = ''}) async => grant;
  @override
  Future<String?> readKey() async => storedKey;
  @override
  Future<void> writeKey(String key) async => storedKey = key;
  @override
  Future<void> deleteKey() async => storedKey = null;
}

class AlwaysTrustKnownHostsStore implements KnownHostsStore {
  @override
  Future<HostKeyVerification> verify(
          String host, int port, String keyType, Uint8List fingerprintBytes) async =>
      HostKeyVerification.trusted;
  @override
  Future<void> forget(String host, int port) async {}
  @override
  Future<void> init() async {}
  @override
  Future<void> trust(String host, int port, String keyType, Uint8List fingerprintBytes) async {}

  @override
  Future<void> trustFingerprint(String host, int port, String keyType, String fingerprint) async {}
}

SwitchableBackend? _backend;

SwitchableBackend get sharedBackend =>
    _backend ??= SwitchableBackend();

bool _hiveReady = false;

Future<ProviderContainer> initApp() async {
  if (!_hiveReady) {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(HostAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(AuthTypeAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SshKeyAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(SessionAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(ForwardTypeAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(ForwardRuleAdapter());
    if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(KnownHostAdapter());
    _hiveReady = true;
  }
  final hostStore = HostStore();
  await hostStore.init();

  final vault = VaultService(sharedBackend);

  return ProviderContainer(overrides: [
    hostStoreProvider.overrideWithValue(hostStore),
    settingsProvider.overrideWith((ref) => SettingsNotifier(loadFromStorage: false)),
    knownHostsStoreProvider.overrideWithValue(AlwaysTrustKnownHostsStore()),
    vaultServiceProvider.overrideWithValue(vault),
    appLockProvider.overrideWith(
      (ref) => AppLockNotifier(vault, hostStore, initiallyLocked: false),
    ),
  ]);
}

Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const PicshellApp(),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// Connects a real session to the docker sshd and selects its tab so the
/// terminal view is mounted. Returns the connected session's terminal.
Future<dynamic> connectSession(
    WidgetTester tester, ProviderContainer container) async {
  final config = SshConnectionConfig(
    host: sshHost,
    port: sshPort,
    username: sshUser,
    authMethod: SshAuthMethod.password,
    password: sshPass,
  );
  final notifier = container.read(sessionListProvider.notifier);
  await notifier.openSession(
    Host(
      id: 'feat-test',
      name: 'feat-test',
      hostname: sshHost,
      port: sshPort,
      username: sshUser,
      authType: AuthType.password,
      password: sshPass,
    ),
    config,
  );
  for (int i = 0; i < 60; i++) {
    await tester.pump(const Duration(seconds: 1));
    final sessions = container.read(sessionListProvider);
    if (sessions.isNotEmpty && sessions.first.connected) break;
  }
  final sessions = container.read(sessionListProvider);
  expect(sessions, isNotEmpty, reason: 'session should connect');
  expect(sessions.first.connected, isTrue, reason: 'session should be connected');
  container.read(selectedSessionIndexProvider.notifier).state = 0;
  await tester.pumpAndSettle(const Duration(seconds: 1));
  return sessions.first.terminal;
}

/// Closes sessions and lets real-async transport teardown drain so the
/// live-binding frames stay clean.
Future<void> teardownSessions(
    WidgetTester tester, ProviderContainer container) async {
  final notifier = container.read(sessionListProvider.notifier);
  for (final s in container.read(sessionListProvider)) {
    try {
      notifier.closeSession(s.id);
    } catch (_) {}
  }
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
}
