import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../providers/host_provider.dart';
import '../providers/key_provider.dart';
import '../services/key_import_service.dart';
import '../services/ssh_service.dart';

class ConnectionDialog extends ConsumerStatefulWidget {
  final void Function(Host host, SshConnectionConfig config) onConnect;

  const ConnectionDialog({super.key, required this.onConnect});

  @override
  ConsumerState<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends ConsumerState<ConnectionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  Host? _selectedSavedHost;
  String _authType = 'password';
  SshKey? _selectedKey;

  String? _validateHost(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Host is required' : null;

  String? _validateUsername(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Username is required' : null;

  String? _validatePort(String? v) {
    final port = int.tryParse(v ?? '');
    if (port == null || port < 1 || port > 65535) {
      return 'Port must be 1–65535';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(hostListProvider);
    final keys = ref.watch(keyListProvider);

    return AlertDialog(
      title: const Text('New Connection'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
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
                        _passwordController.text = host.password ?? '';
                        switch (host.authType) {
                          case AuthType.key:
                            _authType = 'key';
                            break;
                          case AuthType.agent:
                            _authType = 'agent';
                            break;
                          case AuthType.password:
                            _authType = 'password';
                            break;
                        }
                        _selectedKey = host.keyId == null
                            ? null
                            : (keys.any((k) => k.id == host.keyId)
                                ? keys.firstWhere((k) => k.id == host.keyId)
                                : null);
                      }
                    });
                  },
                ),
                const Divider(),
              ],
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(labelText: 'Host'),
                validator: _validateHost,
              ),
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
                validator: _validatePort,
              ),
              TextFormField(
                controller: _userController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: _validateUsername,
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
                TextFormField(
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
                          (k) => DropdownMenuItem(
                              value: k, child: Text(k.name)),
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
    try {
      final key = await KeyImportService.importFromFile();
      if (!mounted) return;
      if (key != null) {
        await ref.read(keyListProvider.notifier).add(key);
        if (!mounted) return;
        setState(() => _selectedKey = key);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Key import failed: $e')),
      );
    }
  }

  void _connect() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final authType = _authType == 'key'
        ? AuthType.key
        : _authType == 'agent'
            ? AuthType.agent
            : AuthType.password;
    final password =
        _authType == 'password' ? _passwordController.text : null;

    if (_authType == 'key' && _selectedKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Select or import a key for key authentication.')),
      );
      return;
    }

    // Field values always come from the controllers so user edits to a
    // pre-filled saved host are honoured; the saved host only contributes
    // its identity (id/name).
    final host = Host(
      id: _selectedSavedHost?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _selectedSavedHost?.name ?? _hostController.text,
      hostname: _hostController.text.trim(),
      port: int.parse(_portController.text),
      username: _userController.text.trim(),
      authType: authType,
      keyId: _selectedKey?.id,
      password: password,
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
