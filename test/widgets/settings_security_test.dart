import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/providers/host_provider.dart';
import 'package:picshell/providers/settings_provider.dart';
import 'package:picshell/providers/vault_provider.dart';
import 'package:picshell/screens/settings/settings_screen.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/services/vault_service.dart';

/// Records vault operations so tests can assert on the auth gate.
class _RecordingBackend implements VaultBackend {
  bool authResult = true;
  int authCalls = 0;
  int deleteKeyCalls = 0;
  String? storedKey;

  _RecordingBackend();

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<bool> authenticate({String reason = ''}) async {
    authCalls++;
    return authResult;
  }

  @override
  Future<String?> readKey() async => storedKey;

  @override
  Future<void> writeKey(String key) async => storedKey = key;

  @override
  Future<void> deleteKey() async {
    deleteKeyCalls++;
    storedKey = null;
  }
}

class _FakeHostStore implements HostStore {
  final List<String> reEncryptCalls = [];

  @override
  Future<void> init() async {}

  @override
  List<Host> getHosts() => [];

  @override
  Future<void> addHost(Host host) async {}

  @override
  Future<void> updateHost(Host host) async {}

  @override
  Future<void> deleteHost(String id) async {}

  @override
  Host? getHost(String id) => null;

  @override
  List<SshKey> getKeys() => [];

  @override
  Future<void> addKey(SshKey key) async {}

  @override
  Future<void> deleteKey(String id) async {}

  @override
  SshKey? getKey(String id) => null;

  @override
  List<Session> getSessions() => [];

  @override
  Future<void> saveSession(Session session) async {}

  @override
  Future<void> deleteSession(String id) async {}

  @override
  bool get isEncrypting => false;

  @override
  void setPassphrase(String passphrase) {}

  @override
  Future<void> reEncryptAll(String newPassphrase) async {
    reEncryptCalls.add(newPassphrase);
  }
}

void main() {
  Future<(WidgetTester, _RecordingBackend, _FakeHostStore, ProviderContainer)>
      _pump(WidgetTester tester, {bool startEnabled = false}) async {
    final backend = _RecordingBackend();
    final vault = VaultService(backend);
    final hostStore = _FakeHostStore();
    final container = ProviderContainer(overrides: [
      hostStoreProvider.overrideWithValue(hostStore),
      // persist: false keeps the notifier off real Hive file IO, which never
      // completes inside a fake-async test zone and would wedge later tests.
      settingsProvider.overrideWith(
          (ref) => SettingsNotifier(loadFromStorage: false, persist: false)),
      vaultServiceProvider.overrideWithValue(vault),
    ]);
    if (startEnabled) {
      container.read(settingsProvider.notifier).setRequireBiometric(true);
    }
    // The security section sits below the fold of the lazy ListView on the
    // default test surface — enlarge it so the toggles are built.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (tester, backend, hostStore, container);
  }

  group('vault toggle auth gate', () {
    testWidgets('enable prompts for verification and aborts on failure',
        (tester) async {
      final (_, backend, hostStore, container) = await _pump(tester);
      backend.authResult = false;

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      // Confirmation dialog first.
      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();

      expect(backend.authCalls, 1, reason: 'enabling must verify the user');
      expect(hostStore.reEncryptCalls, isEmpty,
          reason: 'no re-encryption without successful verification');
      expect(container.read(settingsProvider).requireBiometric, isFalse);
      container.dispose();
    });

    testWidgets('enable proceeds after successful verification', (tester) async {
      final (_, backend, hostStore, container) = await _pump(tester);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();

      expect(backend.authCalls, 1);
      expect(hostStore.reEncryptCalls, hasLength(1));
      // Re-encrypted under the enrolled master key (non-empty).
      expect(hostStore.reEncryptCalls.single, isNotEmpty);
      expect(container.read(settingsProvider).requireBiometric, isTrue);
      container.dispose();
    });

    testWidgets('disable prompts for verification and aborts on failure',
        (tester) async {
      final (_, backend, hostStore, container) = await _pump(tester, startEnabled: true);
      await tester.pump();
      backend.authResult = false;

      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(backend.authCalls, 1, reason: 'disabling must verify the user');
      expect(hostStore.reEncryptCalls, isEmpty,
          reason: 'no plaintext rewrite without successful verification');
      expect(backend.deleteKeyCalls, 0, reason: 'key must not be dropped');
      expect(container.read(settingsProvider).requireBiometric, isTrue);
      container.dispose();
    });

    testWidgets('disable proceeds after successful verification',
        (tester) async {
      final (_, backend, hostStore, container) = await _pump(tester, startEnabled: true);
      // (enabled via _pump's runAsync above)

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(backend.authCalls, 1);
      expect(hostStore.reEncryptCalls, [''],
          reason: 'disabling re-writes everything as plaintext');
      expect(backend.deleteKeyCalls, 1);
      expect(container.read(settingsProvider).requireBiometric, isFalse);
      container.dispose();
    });
  });
}
