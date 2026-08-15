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
import 'package:picshell/widgets/launch_gate_bypassed_banner.dart';

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
  final List<bool> requireFlagAtReEncrypt = [];

  /// When set, its value is read at each reEncryptAll call to record what the
  /// persisted requireBiometric flag was at that moment (ordering assertions).
  bool Function()? probeRequireBiometric;

  /// When set, reEncryptAll throws this instead of succeeding.
  Object? reEncryptError;

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
    if (probeRequireBiometric != null) {
      requireFlagAtReEncrypt.add(probeRequireBiometric!());
    }
    reEncryptCalls.add(newPassphrase);
    if (reEncryptError != null) throw reEncryptError!;
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

      await tester.tap(find.descendant(
        of: find.ancestor(
            of: find.text('Require biometric unlock'),
            matching: find.byType(SwitchListTile)),
        matching: find.byType(Switch)));
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

      await tester.tap(find.descendant(
        of: find.ancestor(
            of: find.text('Require biometric unlock'),
            matching: find.byType(SwitchListTile)),
        matching: find.byType(Switch)));
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

      await tester.tap(find.descendant(
        of: find.ancestor(
            of: find.text('Require biometric unlock'),
            matching: find.byType(SwitchListTile)),
        matching: find.byType(Switch)));
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

      await tester.tap(find.descendant(
        of: find.ancestor(
            of: find.text('Require biometric unlock'),
            matching: find.byType(SwitchListTile)),
        matching: find.byType(Switch)));
      await tester.pumpAndSettle();

      expect(backend.authCalls, 1);
      expect(hostStore.reEncryptCalls, [''],
          reason: 'disabling re-writes everything as plaintext');
      expect(backend.deleteKeyCalls, 1);
      expect(container.read(settingsProvider).requireBiometric, isFalse);
      container.dispose();
    });
  });

  group('crash-safe enable ordering and error feedback', () {
    testWidgets('enable persists requireBiometric BEFORE re-encrypting',
        (tester) async {
      final (_, backend, hostStore, container) = await _pump(tester);
      hostStore.probeRequireBiometric =
          () => container.read(settingsProvider).requireBiometric;

      await tester.tap(find.descendant(
        of: find.ancestor(
            of: find.text('Require biometric unlock'),
            matching: find.byType(SwitchListTile)),
        matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();

      expect(hostStore.reEncryptCalls, hasLength(1));
      expect(hostStore.requireFlagAtReEncrypt, [true],
          reason: 'a crash right before reEncryptAll must leave the flag on '
              'so the next launch prompts and releases the enrolled key');
      expect(container.read(settingsProvider).requireBiometric, isTrue);
      container.dispose();
    });

    testWidgets('enable failure rolls the flag back and shows an error snackbar',
        (tester) async {
      final (_, backend, hostStore, container) = await _pump(tester);
      hostStore.reEncryptError =
          StateError('reEncryptAll aborted: 1 record(s) failed to decrypt');

      await tester.tap(find.descendant(
        of: find.ancestor(
            of: find.text('Require biometric unlock'),
            matching: find.byType(SwitchListTile)),
        matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).requireBiometric, isFalse,
          reason: 'the persisted flag must match the unchanged on-disk state');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Failed to enable biometric encryption'),
          findsOneWidget);
      container.dispose();
    });

    testWidgets('disable failure keeps the flag, keeps the key, and shows an '
        'error snackbar', (tester) async {
      final (_, backend, hostStore, container) =
          await _pump(tester, startEnabled: true);
      hostStore.reEncryptError = StateError('boom');

      await tester.tap(find.descendant(
        of: find.ancestor(
            of: find.text('Require biometric unlock'),
            matching: find.byType(SwitchListTile)),
        matching: find.byType(Switch)));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).requireBiometric, isTrue);
      expect(backend.deleteKeyCalls, 0, reason: 'key must not be dropped');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Failed to disable biometric encryption'),
          findsOneWidget);
      container.dispose();
    });
  });

  group('launch gate bypassed banner', () {
    testWidgets('shows a warning banner when the provider is non-null',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            launchSecurityWarningProvider
                .overrideWithValue('gate was bypassed warning text'),
          ],
          child: const MaterialApp(
            home: Scaffold(body: LaunchGateBypassedBanner(child: Text('app'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.textContaining('gate was bypassed warning text'),
          findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('shows nothing when the gate was enforced', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: LaunchGateBypassedBanner(child: Text('app'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
    });
  });
}
