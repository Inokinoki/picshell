import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:picshell/app/app.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/providers/host_provider.dart';

Future<ProviderContainer> _initApp() async {
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(HostAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(AuthTypeAdapter());

  final hostStore = HostStore();
  await hostStore.init();

  return ProviderContainer(overrides: [
    hostStoreProvider.overrideWithValue(hostStore),
  ]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App launch', () {
    testWidgets('app starts and shows home screen', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Picshell'), findsOneWidget);
      container.dispose();
    });

    testWidgets('shows new connection button', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byTooltip('New Connection (Ctrl+N)'), findsOneWidget);
      container.dispose();
    });

    testWidgets('shows manage hosts button', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byTooltip('Manage Hosts'), findsOneWidget);
      container.dispose();
    });

    testWidgets('shows empty state when no sessions', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('No active sessions'), findsOneWidget);
      container.dispose();
    });
  });

  group('Connection dialog', () {
    testWidgets('tapping new connection opens dialog', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.byTooltip('New Connection (Ctrl+N)'));
      await tester.pumpAndSettle();

      expect(find.text('Host'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      container.dispose();
    });

    testWidgets('Cancel closes dialog', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.byTooltip('New Connection (Ctrl+N)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Host'), findsNothing);
      container.dispose();
    });

    testWidgets('dialog has Connect button', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.byTooltip('New Connection (Ctrl+N)'));
      await tester.pumpAndSettle();

      expect(find.text('Connect'), findsOneWidget);
      container.dispose();
    });
  });

  group('SSH connection flow', () {
    testWidgets('invalid host shows error snackbar', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.byTooltip('New Connection (Ctrl+N)'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Host'), '192.0.2.1');
      await tester.enterText(
          find.widgetWithText(TextField, 'Username'), 'test');

      final passwordFields = find.widgetWithText(TextField, 'Password');
      if (passwordFields.evaluate().isNotEmpty) {
        await tester.enterText(passwordFields.first, 'test');
      }

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle(const Duration(seconds: 12));

      expect(find.byType(SnackBar), findsOneWidget);
      container.dispose();
    });

    testWidgets('empty host field still attempts connection', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.byTooltip('New Connection (Ctrl+N)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pump();

      container.dispose();
    });
  });

  group('Navigation', () {
    testWidgets('navigate to settings', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsAtLeast(1));
      container.dispose();
    });

    testWidgets('navigate to hosts management', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.byTooltip('Manage Hosts'));
      await tester.pumpAndSettle();

      container.dispose();
    });
  });
}
