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
import 'package:picshell/providers/settings_provider.dart';

bool _hiveReady = false;

Future<ProviderContainer> _initApp() async {
  if (!_hiveReady) {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(HostAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(AuthTypeAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SshKeyAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(SessionAdapter());
    _hiveReady = true;
  }

  final hostStore = HostStore();
  await hostStore.init();

  return ProviderContainer(overrides: [
    hostStoreProvider.overrideWithValue(hostStore),
    settingsProvider.overrideWith(
      (ref) => SettingsNotifier(loadFromStorage: false),
    ),
  ]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App launch', () {
    testWidgets('shows home screen with title', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Picshell'), findsOneWidget);
      container.dispose();
    });

    testWidgets('shows toolbar buttons', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byTooltip('New Connection (Ctrl+N)'), findsOneWidget);
      expect(find.byTooltip('Manage Hosts'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      container.dispose();
    });

    testWidgets('shows empty state', (tester) async {
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
    testWidgets('opens dialog with form fields', (tester) async {
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
      expect(find.text('Auth Method'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      container.dispose();
    });

    testWidgets('port defaults to 22', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.byTooltip('New Connection (Ctrl+N)'));
      await tester.pumpAndSettle();

      final portField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Port'),
      );
      expect(portField.controller!.text, '22');
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
      expect(find.text('Host'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Host'), findsNothing);
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
  });
}
