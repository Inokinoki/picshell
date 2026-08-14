import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/providers/host_provider.dart';
import 'package:picshell/providers/vault_provider.dart';
import 'package:picshell/screens/lock/lock_screen.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/services/vault_service.dart';

class _FakeBackend implements VaultBackend {
  bool authResult;
  _FakeBackend(this.authResult);
  @override
  Future<bool> get canCheckBiometrics async => true;
  @override
  Future<bool> authenticate({String reason = ''}) async => authResult;
  @override
  Future<String?> readKey() async => 'stored-key';
  @override
  Future<void> writeKey(String key) async {}
  @override
  Future<void> deleteKey() async {}
}

void main() {
  group('LockScreen', () {
    testWidgets('failed unlock shows a retry hint', (tester) async {
      final vault = VaultService(_FakeBackend(false));
      final hostStore = HostStore();
      final container = ProviderContainer(overrides: [
        vaultServiceProvider.overrideWithValue(vault),
        hostStoreProvider.overrideWithValue(hostStore),
        appLockProvider.overrideWith(
          (ref) => AppLockNotifier(vault, hostStore, initiallyLocked: true),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LockScreen()),
      ));
      await tester.pump();

      expect(find.text('Picshell is locked'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Unlock'));
      });
      await tester.pumpAndSettle();

      // Auth returned false → still locked, retry hint shown.
      expect(find.textContaining('Unlock failed'), findsOneWidget);
      expect(container.read(appLockProvider), isTrue);
    });

    testWidgets('successful unlock flips the provider to unlocked',
        (tester) async {
      final vault = VaultService(_FakeBackend(true));
      final hostStore = HostStore();
      final container = ProviderContainer(overrides: [
        vaultServiceProvider.overrideWithValue(vault),
        hostStoreProvider.overrideWithValue(hostStore),
        appLockProvider.overrideWith(
          (ref) => AppLockNotifier(vault, hostStore, initiallyLocked: true),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LockScreen()),
      ));
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text('Unlock'));
      });
      // Process microtasks so the async unlock() completes. Avoid
      // pumpAndSettle: on success the button stays in its busy (spinner)
      // state until the app swaps away, whose animation never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(container.read(appLockProvider), isFalse);
      expect(hostStore.isEncrypting, isTrue); // master key released
    });
  });
}
