import 'package:go_router/go_router.dart';
import '../screens/home/home_screen.dart';
import '../screens/hosts/host_list_screen.dart';
import '../screens/hosts/host_edit_screen.dart';
import '../screens/keys/key_list_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/sftp/sftp_browser_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/hosts',
      builder: (context, state) => const HostListScreen(),
    ),
    GoRoute(
      path: '/hosts/edit',
      builder: (context, state) => const HostEditScreen(),
    ),
    GoRoute(
      path: '/hosts/edit/:id',
      builder: (context, state) =>
          HostEditScreen(hostId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/keys',
      builder: (context, state) => const KeyListScreen(),
    ),
    GoRoute(
      path: '/sftp/:sessionId',
      builder: (context, state) => SftpBrowserScreen(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
