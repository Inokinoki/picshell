import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../models/host.dart';
import '../../providers/host_provider.dart';

class HostEditScreen extends ConsumerStatefulWidget {
  final String? hostId;

  const HostEditScreen({super.key, this.hostId});

  @override
  ConsumerState<HostEditScreen> createState() => _HostEditScreenState();
}

class _HostEditScreenState extends ConsumerState<HostEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _userController = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    if (widget.hostId != null) {
      _isEditing = true;
      final hosts = ref.read(hostListProvider);
      final host = hosts.firstWhere((h) => h.id == widget.hostId);
      _nameController.text = host.name;
      _hostController.text = host.hostname;
      _portController.text = host.port.toString();
      _userController.text = host.username;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Host' : 'Add Host'),
        actions: [IconButton(icon: const Icon(Icons.save), onPressed: _save)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Display Name'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(labelText: 'Hostname / IP'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: _userController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final notifier = ref.read(hostListProvider.notifier);

    if (_isEditing) {
      final hosts = ref.read(hostListProvider);
      final host = hosts.firstWhere((h) => h.id == widget.hostId);
      host.name = _nameController.text;
      host.hostname = _hostController.text;
      host.port = int.tryParse(_portController.text) ?? 22;
      host.username = _userController.text;
      notifier.update(host);
    } else {
      final host = Host(
        id: const Uuid().v4(),
        name: _nameController.text,
        hostname: _hostController.text,
        port: int.tryParse(_portController.text) ?? 22,
        username: _userController.text,
      );
      notifier.add(host);
    }

    Navigator.pop(context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    super.dispose();
  }
}
