import 'package:flutter/material.dart';

class PicshellApp extends StatelessWidget {
  const PicshellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Picshell',
      theme: ThemeData.dark(),
      home: const Scaffold(body: Center(child: Text('Picshell'))),
    );
  }
}
