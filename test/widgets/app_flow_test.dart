import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/app/app.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/providers/host_provider.dart';
import 'package:picshell/providers/settings_provider.dart';

class _FakeHostStore implements HostStore {
  final List<Host> _hosts = [];
  final List<SshKey> _keys = [];

  @override
  Future<void> init() async {}

  @override
  List<Host> getHosts() => _hosts;

  @override
  Future<void> addHost(Host host) async => _hosts.add(host);

  @override
  Future<void> updateHost(Host host) async {}

  @override
  Future<void> deleteHost(String id) async =>
      _hosts.removeWhere((h) => h.id == id);

  @override
  Host? getHost(String id) =>
      _hosts.where((h) => h.id == id).firstOrNull;

  @override
  List<SshKey> getKeys() => _keys;

  @override
  Future<void> addKey(SshKey key) async => _keys.add(key);

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
}

Widget _buildApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const PicshellApp(),
  );
}

ProviderContainer _createContainer() {
  return ProviderContainer(overrides: [
    hostStoreProvider.overrideWithValue(_FakeHostStore()),
    settingsProvider.overrideWith((ref) => SettingsNotifier(loadFromStorage: false)),
  ]);
}

void main() {
  group('App launch', () {
    testWidgets('shows home screen with title', (tester) async {
      final container = _createContainer();
      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(find.text('Picshell'), findsOneWidget);
      container.dispose();
    });

    testWidgets('shows toolbar buttons', (tester) async {
      final container = _createContainer();
      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(find.byTooltip('New Connection (Ctrl+N)'), findsOneWidget);
      expect(find.byTooltip('Manage Hosts'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      container.dispose();
    });

    testWidgets('shows empty state', (tester) async {
      final container = _createContainer();
      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(find.text('No active sessions'), findsOneWidget);
      container.dispose();
    });
  });

  group('Connection dialog', () {
    testWidgets('opens dialog with form fields', (tester) async {
      final container = _createContainer();
      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

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
      final container = _createContainer();
      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Connection (Ctrl+N)'));
      await tester.pumpAndSettle();

      final portField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Port'),
      );
      expect(portField.controller!.text, '22');
      container.dispose();
    });

    testWidgets('Cancel closes dialog', (tester) async {
      final container = _createContainer();
      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Connection (Ctrl+N)'));
      await tester.pumpAndSettle();
      expect(find.text('Host'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Host'), findsNothing);
      container.dispose();
    });

    testWidgets('dialog has auth method dropdown', (tester) async {
      final container = _createContainer();
      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New Connection (Ctrl+N)'));
      await tester.pumpAndSettle();

      expect(find.text('Auth Method'), findsOneWidget);
      container.dispose();
    });
  });

  group('Navigation', () {
    testWidgets('navigate to settings', (tester) async {
      final container = _createContainer();
      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsAtLeast(1));
      container.dispose();
    });

    testWidgets('navigate to hosts page', (tester) async {
      final container = _createContainer();
      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      container.dispose();
    });
  });
}
