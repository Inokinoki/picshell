import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/host.dart';
import '../../providers/host_provider.dart';

class HostListScreen extends ConsumerWidget {
  const HostListScreen({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Host host,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${host.name}?'),
        content: const Text(
          'The saved host and its stored password will be removed. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      ref.read(hostListProvider.notifier).delete(host.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Hosts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/hosts/edit'),
          ),
        ],
      ),
      body: hosts.isEmpty
          ? const Center(child: Text('No saved hosts'))
          : ListView.builder(
              itemCount: hosts.length,
              itemBuilder: (context, index) {
                final host = hosts[index];
                return ListTile(
                  title: Text(host.name),
                  subtitle: Text(
                    '${host.username}@${host.hostname}:${host.port}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _confirmDelete(context, ref, host),
                  ),
                  onTap: () => context.push('/hosts/edit/${host.id}'),
                );
              },
            ),
    );
  }
}
