import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/host.dart';
import '../../providers/session_provider.dart';
import '../../services/ssh_service.dart';
import '../../widgets/connection_dialog.dart';
import '../terminal/terminal_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Picshell'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns),
            onPressed: () => context.push('/hosts'),
            tooltip: 'Manage Hosts',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showConnectDialog(context, ref),
            tooltip: 'New Connection',
          ),
        ],
        bottom: sessions.isNotEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: _SessionTabBar(
                  sessions: sessions,
                  onClose: (id) =>
                      ref.read(sessionListProvider.notifier).closeSession(id),
                ),
              )
            : null,
      ),
      body: sessions.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.terminal, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No active sessions',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showConnectDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('New Connection'),
                  ),
                ],
              ),
            )
          : _SessionView(sessions: sessions),
    );
  }

  void _showConnectDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => ConnectionDialog(
        onConnect: (Host host, SshConnectionConfig config) async {
          try {
            await ref
                .read(sessionListProvider.notifier)
                .openSession(host, config);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Connection failed: $e')));
            }
          }
        },
      ),
    );
  }
}

class _SessionTabBar extends StatelessWidget {
  final List<SessionState> sessions;
  final void Function(String id) onClose;

  const _SessionTabBar({required this.sessions, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Chip(
              label: Text(
                session.host.name,
                style: const TextStyle(fontSize: 12),
              ),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () => onClose(session.id),
              backgroundColor: session.connected
                  ? Colors.teal.shade900
                  : Colors.red.shade900,
            ),
          );
        },
      ),
    );
  }
}

class _SessionView extends StatelessWidget {
  final List<SessionState> sessions;

  const _SessionView({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final session = sessions.last;
    return TerminalScreen(sshService: session.sshService);
  }
}
