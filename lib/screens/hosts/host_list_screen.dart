import 'package:flutter/material.dart';

class HostListScreen extends StatelessWidget {
  const HostListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hosts')),
      body: const Center(child: Text('Host List')),
    );
  }
}
