import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/host.dart';
import '../providers/host_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(hostListProvider);

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
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final host =
                _selectedSavedHost ??
                Host(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: _hostController.text,
                  hostname: _hostController.text,
                  port: int.tryParse(_portController.text) ?? 22,
                  username: _userController.text,
                );

            final config = SshConnectionConfig(
              host: host.hostname,
              port: host.port,
              username: host.username,
              authMethod: SshAuthMethod.password,
              password: _passwordController.text,
            );

            widget.onConnect(host, config);
            Navigator.pop(context);
          },
          child: const Text('Connect'),
        ),
      ],
    );
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
