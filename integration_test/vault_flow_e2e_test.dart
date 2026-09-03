import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/providers/settings_provider.dart';
import 'package:picshell/providers/vault_provider.dart';
import 'package:integration_test/integration_test.dart';
import 'package:picshell/screens/lock/lock_screen.dart';

import 'helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Vault: enable requires verification, lock shows the gate, failed '
      'unlock stays locked, successful unlock releases',
      (tester) async {
    final container = await initApp();
    await pumpApp(tester, container);

    // Enable: Settings → security switch → confirm dialog. Toggling the
    // vault on requires a successful user verification first, so the fake
    // backend must grant.
    sharedBackend.grant = true;
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final switchFinder = find.text('Require biometric unlock');
    // The security section sits below the fold in a lazy ListView.
    await tester.scrollUntilVisible(switchFinder, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(find.text('Enable biometric encryption'), findsOneWidget,
        reason: 'confirm dialog should open after toggling the switch');
    await tester.tap(find.text('Enable'));
    // The enable chain (authenticate → getMasterKey → persist → re-encrypt)
    // runs on real async I/O; poll until the flag lands instead of guessing
    // how long it takes.
    await tester.runAsync(() async {
      for (int i = 0; i < 100; i++) {
        if (container.read(settingsProvider).requireBiometric) return;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });

    expect(container.read(settingsProvider).requireBiometric, isTrue,
        reason: 'enable flow should persist requireBiometric');

    // Lock: the gate renders instead of the app.
    container.read(appLockProvider.notifier).lock();
    await tester.pumpAndSettle();
    expect(container.read(appLockProvider), isTrue,
        reason: 'notifier should be locked');
    expect(find.byType(LockScreen), findsOneWidget,
        reason: 'lock screen should render');

    // Failed verification stays locked.
    sharedBackend.grant = false;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(LockScreen), findsOneWidget,
        reason: 'cancelled biometrics must keep the gate up');

    // Successful verification releases the gate.
    sharedBackend.grant = true;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(LockScreen), findsNothing,
        reason: 'successful unlock should return to the app');

    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
