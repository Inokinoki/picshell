import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/providers/host_provider.dart';
import 'package:picshell/providers/session_provider.dart';
import 'package:picshell/providers/settings_provider.dart';
import 'package:picshell/screens/home/home_screen.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/services/ssh_service.dart';
import 'package:xterm/xterm.dart';

class _FakeHostStore implements HostStore {
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
}

SessionState _session({required bool connected, required String id}) {
  return SessionState(
    id: id,
    host: Host(
      id: 'h1',
      name: 'test',
      hostname: '1.2.3.4',
      username: 'u',
    ),
    sshService: SshService(),
    terminal: Terminal(maxLines: 100),
    connected: connected,
  );
}

Widget _buildHome(ProviderContainer container) {
  // Wrap HomeScreen in a MaterialApp.router so context.push works.
  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreen())],
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('shows Open SFTP button when session connected', (tester) async {
    final container = ProviderContainer(overrides: [
      hostStoreProvider.overrideWithValue(_FakeHostStore()),
      settingsProvider.overrideWith((ref) => SettingsNotifier(loadFromStorage: false)),
    ]);
    container.read(sessionListProvider.notifier).debugAddSession(
          _session(connected: true, id: 'sess-1'),
        );
    await tester.pumpWidget(_buildHome(container));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open SFTP'), findsOneWidget);
    container.dispose();
  });

  testWidgets('hides Open SFTP button when not connected', (tester) async {
    final container = ProviderContainer(overrides: [
      hostStoreProvider.overrideWithValue(_FakeHostStore()),
      settingsProvider.overrideWith((ref) => SettingsNotifier(loadFromStorage: false)),
    ]);
    container.read(sessionListProvider.notifier).debugAddSession(
          _session(connected: false, id: 'sess-1'),
        );
    await tester.pumpWidget(_buildHome(container));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open SFTP'), findsNothing);
    container.dispose();
  });

  testWidgets('tapping Open SFP navigates to /sftp/:id', (tester) async {
    final container = ProviderContainer(overrides: [
      hostStoreProvider.overrideWithValue(_FakeHostStore()),
      settingsProvider.overrideWith((ref) => SettingsNotifier(loadFromStorage: false)),
    ]);
    container.read(sessionListProvider.notifier).debugAddSession(
          _session(connected: true, id: 'sess-42'),
        );
    // A router that captures the destination so we don't need the real
    // SftpBrowserScreen (which would try to resolve a real session backend).
    String? pushed;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(
          path: '/sftp/:sessionId',
          builder: (c, s) {
            pushed = s.pathParameters['sessionId'];
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open SFTP'));
    await tester.pumpAndSettle();

    expect(pushed, 'sess-42');
    container.dispose();
  });
}
