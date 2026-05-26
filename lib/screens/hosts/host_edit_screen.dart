import 'package:flutter/material.dart';

class HostEditScreen extends StatelessWidget {
  final String? hostId;

  const HostEditScreen({super.key, this.hostId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Host')),
      body: const Center(child: Text('Host Edit')),
    );
  }
}
