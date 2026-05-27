import 'package:go_router/go_router.dart';
import '../screens/home/home_screen.dart';
import '../screens/hosts/host_list_screen.dart';
import '../screens/hosts/host_edit_screen.dart';
import '../screens/settings/settings_screen.dart';

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
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
