import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/host.dart';
import '../../providers/session_provider.dart';
import '../../services/ssh_service.dart';
import '../../widgets/connection_dialog.dart';
import '../terminal/terminal_screen.dart';

final selectedSessionIndexProvider = StateProvider<int>((ref) => 0);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionListProvider);
    final selectedIndex = ref.watch(selectedSessionIndexProvider);

    final clampedIndex = sessions.isEmpty
        ? 0
        : selectedIndex.clamp(0, sessions.length - 1);

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
                  selectedIndex: clampedIndex,
                  onSelect: (index) =>
                      ref.read(selectedSessionIndexProvider.notifier).state =
                          index,
                  onClose: (id) {
                    ref.read(sessionListProvider.notifier).closeSession(id);
                    final current = ref.read(selectedSessionIndexProvider);
                    final newSessions = ref.read(sessionListProvider);
                    if (current >= newSessions.length &&
                        newSessions.isNotEmpty) {
                      ref.read(selectedSessionIndexProvider.notifier).state =
                          newSessions.length - 1;
                    }
                  },
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
          : _SessionView(sessions: sessions, selectedIndex: clampedIndex),
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
            final newSessions = ref.read(sessionListProvider);
            ref.read(selectedSessionIndexProvider.notifier).state =
                newSessions.length - 1;
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
  final int selectedIndex;
  final void Function(int index) onSelect;
  final void Function(String id) onClose;

  const _SessionTabBar({
    required this.sessions,
    required this.selectedIndex,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
          final isSelected = index == selectedIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onSelect(index),
              child: Chip(
                label: Text(
                  session.host.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                deleteIcon: const Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.white70,
                ),
                onDeleted: () => onClose(session.id),
                backgroundColor: isSelected
                    ? Colors.teal.shade700
                    : session.connected
                    ? Colors.teal.shade900
                    : Colors.red.shade900,
                side: isSelected
                    ? const BorderSide(color: Colors.tealAccent, width: 2)
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SessionView extends StatelessWidget {
  final List<SessionState> sessions;
  final int selectedIndex;

  const _SessionView({required this.sessions, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    final session = sessions[selectedIndex];
    return TerminalScreen(terminal: session.terminal);
  }
}
