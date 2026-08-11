import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../models/host.dart';
import '../../providers/host_provider.dart';
import '../../providers/key_provider.dart';

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
  final _passwordController = TextEditingController();
  AuthType _authType = AuthType.password;
  String? _selectedKeyId;
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
      _authType = host.authType;
      _passwordController.text = host.password ?? '';
      _selectedKeyId = host.keyId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(keyListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Host' : 'Add Host'),
        actions: [IconButton(icon: const Icon(Icons.save), onPressed: _save)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Display Name'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              TextFormField(
                controller: _hostController,
                decoration:
                    const InputDecoration(labelText: 'Hostname / IP'),
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
              Text(
                'Authentication',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ListTile(
                title: const Text('Password'),
                leading: Radio<AuthType>(
                  value: AuthType.password,
                  groupValue: _authType,
                  onChanged: (v) => setState(() => _authType = v!),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_authType == AuthType.password)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                ),
              ListTile(
                title: const Text('SSH Key'),
                leading: Radio<AuthType>(
                  value: AuthType.key,
                  groupValue: _authType,
                  onChanged: (v) => setState(() => _authType = v!),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_authType == AuthType.key)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: keys.isEmpty
                            ? const Text(
                                'No keys imported yet',
                                style: TextStyle(color: Colors.grey),
                              )
                            : DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  labelText: 'Select Key',
                                  border: OutlineInputBorder(),
                                ),
                                value: _selectedKeyId,
                                items: keys
                                    .map(
                                      (k) => DropdownMenuItem(
                                        value: k.id,
                                        child: Text(k.name),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (id) =>
                                    setState(() => _selectedKeyId = id),
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.vpn_key),
                        tooltip: 'Manage SSH Keys',
                        onPressed: () => context.push('/keys'),
                      ),
                    ],
                  ),
                ),
              ListTile(
                title: const Text('SSH Agent'),
                subtitle: const Text(
                  'Uses keys from ~/.ssh/ directory',
                  style: TextStyle(fontSize: 12),
                ),
                leading: Radio<AuthType>(
                  value: AuthType.agent,
                  groupValue: _authType,
                  onChanged: (v) => setState(() => _authType = v!),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
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
    if (_authType == AuthType.key && _selectedKeyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an SSH key')),
      );
      return;
    }

    final notifier = ref.read(hostListProvider.notifier);
    final password =
        _authType == AuthType.password ? _passwordController.text : null;
    final keyId = _authType == AuthType.key ? _selectedKeyId : null;

    if (_isEditing) {
      final hosts = ref.read(hostListProvider);
      final host = hosts.firstWhere((h) => h.id == widget.hostId);
      host.name = _nameController.text;
      host.hostname = _hostController.text;
      host.port = int.tryParse(_portController.text) ?? 22;
      host.username = _userController.text;
      host.authType = _authType;
      host.password = password;
      host.keyId = keyId;
      notifier.update(host);
    } else {
      final host = Host(
        id: const Uuid().v4(),
        name: _nameController.text,
        hostname: _hostController.text,
        port: int.tryParse(_portController.text) ?? 22,
        username: _userController.text,
        authType: _authType,
        password: password,
        keyId: keyId,
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
    _passwordController.dispose();
    super.dispose();
  }
}
