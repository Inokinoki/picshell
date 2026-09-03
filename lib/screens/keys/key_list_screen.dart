import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/host.dart';
import '../../providers/host_provider.dart';
import '../../providers/key_provider.dart';
import '../../services/key_import_service.dart';

class KeyListScreen extends ConsumerWidget {
  const KeyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(keyListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH Keys'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Import Key',
            onPressed: () => _importKey(context, ref),
          ),
        ],
      ),
      body: keys.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.vpn_key_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No SSH keys imported',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _importKey(context, ref),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import Private Key'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final key = keys[index];
                final pubDisplay = key.publicKey.isEmpty
                    ? '(public key unavailable)'
                    : _truncate(key.publicKey, 40);
                return ListTile(
                  leading: const Icon(Icons.vpn_key),
                  title: Text(key.name),
                  subtitle: Text(
                    pubDisplay,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _confirmDelete(context, ref, key.id, key.name),
                  ),
                );
              },
            ),
    );
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  Future<void> _importKey(BuildContext context, WidgetRef ref) async {
    try {
      final key = await KeyImportService.importFromFile();
      if (key != null) {
        await ref.read(keyListProvider.notifier).add(key);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid private key: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String id,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Key'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    ref.read(keyListProvider.notifier).delete(id);

    // Hosts configured for this key would fail opaquely at connect time;
    // switch them back to password auth.
    final hosts = ref.read(hostListProvider);
    for (final host in hosts.where((h) => h.keyId == id)) {
      host.keyId = null;
      host.authType = AuthType.password;
      ref.read(hostListProvider.notifier).update(host);
    }
  }
}
