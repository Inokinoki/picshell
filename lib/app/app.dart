import 'package:flutter/material.dart';
import 'routes.dart';

class PicshellApp extends StatelessWidget {
  const PicshellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Picshell',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        colorScheme: ColorScheme.dark(
          primary: Colors.tealAccent,
          secondary: Colors.tealAccent.shade700,
        ),
      ),
      routerConfig: router,
    );
  }
}
