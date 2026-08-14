import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../providers/vault_provider.dart';
import '../screens/lock/lock_screen.dart';
import 'routes.dart';

class PicshellApp extends ConsumerStatefulWidget {
  const PicshellApp({super.key});

  @override
  ConsumerState<PicshellApp> createState() => _PicshellAppState();
}

class _PicshellAppState extends ConsumerState<PicshellApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-show the lock screen when returning from background, if enabled.
    // The in-memory master key is not cleared in v1 (UI gate only).
    if (state == AppLifecycleState.resumed) {
      final settings = ref.read(settingsProvider);
      if (settings.requireBiometric && settings.relockOnBackground) {
        ref.read(appLockProvider.notifier).lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final locked = ref.watch(appLockProvider);

    final lightTheme = ThemeData.light().copyWith(
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.light(
        primary: Colors.teal,
        secondary: Colors.teal.shade700,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
    );
    final darkTheme = ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      colorScheme: ColorScheme.dark(
        primary: Colors.tealAccent,
        secondary: Colors.tealAccent.shade700,
      ),
    );

    // When locked, render only the gate — do not build the router (and thus
    // the home screen) so no encrypted-at-rest data is read before unlock.
    if (locked) {
      return MaterialApp(
        title: 'Picshell',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: settings.themeMode,
        home: const LockScreen(),
      );
    }

    return MaterialApp.router(
      title: 'Picshell',
      themeMode: settings.themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      routerConfig: router,
    );
  }
}
