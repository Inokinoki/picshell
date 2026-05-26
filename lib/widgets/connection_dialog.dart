import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../providers/host_provider.dart';
import '../providers/key_provider.dart';
import '../services/ssh_service.dart';

class ConnectionDialog extends ConsumerStatefulWidget {
  final void Function(Host host, SshConnectionConfig config) onConnect;

  const ConnectionDialog({super.key, required this.onConnect});

  @override
  ConsumerState<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends ConsumerState<ConnectionDialog> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  Host? _selectedSavedHost;
  String _authType = 'password';
  SshKey? _selectedKey;

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(hostListProvider);
    final keys = ref.watch(keyListProvider);

    return AlertDialog(
      title: const Text('New Connection'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hosts.isNotEmpty) ...[
              DropdownButton<Host>(
                isExpanded: true,
                hint: const Text('Select saved host'),
                value: _selectedSavedHost,
                items: hosts
                    .map(
                      (h) => DropdownMenuItem(
                        value: h,
                        child: Text('${h.name} (${h.hostname})'),
                      ),
                    )
                    .toList(),
                onChanged: (host) {
                  setState(() {
                    _selectedSavedHost = host;
                    if (host != null) {
                      _hostController.text = host.hostname;
                      _portController.text = host.port.toString();
                      _userController.text = host.username;
                      if (host.authType == AuthType.key) {
                        _authType = 'key';
                      }
                    }
                  });
                },
              ),
              const Divider(),
            ],
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(labelText: 'Host'),
            ),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _userController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Auth Method'),
              initialValue: _authType,
              items: const [
                DropdownMenuItem(value: 'password', child: Text('Password')),
                DropdownMenuItem(value: 'key', child: Text('SSH Key')),
                DropdownMenuItem(value: 'agent', child: Text('SSH Agent')),
              ],
              onChanged: (v) => setState(() => _authType = v ?? 'password'),
            ),
            if (_authType == 'password')
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
            if (_authType == 'key') ...[
              const SizedBox(height: 8),
              if (keys.isNotEmpty)
                DropdownButtonFormField<SshKey>(
                  decoration: const InputDecoration(labelText: 'Select Key'),
                  initialValue: _selectedKey,
                  items: keys
                      .map(
                        (k) => DropdownMenuItem(value: k, child: Text(k.name)),
                      )
                      .toList(),
                  onChanged: (key) => setState(() => _selectedKey = key),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _importKey,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import Private Key'),
              ),
            ],
            if (_authType == 'agent')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Uses keys from ~/.ssh/ directory',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _connect, child: const Text('Connect')),
      ],
    );
  }

  Future<void> _importKey() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      final path = file.path;
      if (path != null) {
        final content = await File(path).readAsString();
        final key = SshKey(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: file.name,
          privateKeyPem: content,
          publicKey: '',
        );
        await ref.read(keyListProvider.notifier).add(key);
        setState(() => _selectedKey = key);
      }
    }
  }

  void _connect() {
    final host =
        _selectedSavedHost ??
        Host(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: _hostController.text,
          hostname: _hostController.text,
          port: int.tryParse(_portController.text) ?? 22,
          username: _userController.text,
          authType: _authType == 'key'
              ? AuthType.key
              : _authType == 'agent'
              ? AuthType.key
              : AuthType.password,
          keyId: _selectedKey?.id,
        );

    SshAuthMethod authMethod;
    switch (_authType) {
      case 'key':
        authMethod = SshAuthMethod.key;
        break;
      case 'agent':
        authMethod = SshAuthMethod.agent;
        break;
      default:
        authMethod = SshAuthMethod.password;
    }

    final config = SshConnectionConfig(
      host: host.hostname,
      port: host.port,
      username: host.username,
      authMethod: authMethod,
      password: _authType == 'password' ? _passwordController.text : null,
      privateKeyPem: _authType == 'key' ? _selectedKey?.privateKeyPem : null,
    );

    widget.onConnect(host, config);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
