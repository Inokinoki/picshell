import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/floating_image.dart';
import '../../models/forward_rule.dart';
import '../../models/host.dart';
import '../../providers/floating_image_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/known_hosts_store.dart';
import '../../services/platform_capabilities.dart';
import '../../services/ssh_service.dart';
import '../../widgets/connection_dialog.dart';
import '../../widgets/floating_image_overlay.dart';
import '../../widgets/host_key_dialog.dart';
import '../terminal/terminal_screen.dart';

final selectedSessionIndexProvider = StateProvider<int>((ref) => 0);

class _NewConnectionIntent extends Intent {
  const _NewConnectionIntent();
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionListProvider);
    final selectedIndex = ref.watch(selectedSessionIndexProvider);
    final floatingImages = ref.watch(floatingImagesProvider);
    final minimizedImages = floatingImages
        .where((img) => img.minimized)
        .toList();

    final clampedIndex = sessions.isEmpty
        ? 0
        : selectedIndex.clamp(0, sessions.length - 1);

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
            const _NewConnectionIntent(),
      },
      child: Actions(
        actions: {
          _NewConnectionIntent: CallbackAction<_NewConnectionIntent>(
            onInvoke: (_) => _showConnectDialog(context, ref),
          ),
        },
        child: FloatingImageOverlay(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Picshell'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.dns),
                  onPressed: () => context.push('/hosts'),
                  tooltip: 'Manage Hosts',
                ),
                IconButton(
                  icon: const Icon(Icons.vpn_key),
                  onPressed: () => context.push('/keys'),
                  tooltip: 'Manage SSH Keys',
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showConnectDialog(context, ref),
                  tooltip: 'New Connection (Ctrl+N)',
                ),
                IconButton(
                  icon: const Icon(Icons.compare_arrows),
                  onPressed: sessions.isEmpty
                      ? null
                      : () => _showForwardsSheet(
                            context,
                            sessions[clampedIndex],
                          ),
                  tooltip: 'Port Forwards',
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () => context.push('/settings'),
                  tooltip: 'Settings',
                ),
              ],
              bottom: sessions.isNotEmpty || minimizedImages.isNotEmpty
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(40),
                      child: _SessionTabBar(
                        sessions: sessions,
                        selectedIndex: clampedIndex,
                        onSelect: (index) =>
                            ref
                                    .read(selectedSessionIndexProvider.notifier)
                                    .state =
                                index,
                        onClose: (id) {
                          ref
                              .read(sessionListProvider.notifier)
                              .closeSession(id);
                          final current = ref.read(
                            selectedSessionIndexProvider,
                          );
                          final newSessions = ref.read(sessionListProvider);
                          if (current >= newSessions.length &&
                              newSessions.isNotEmpty) {
                            ref
                                    .read(selectedSessionIndexProvider.notifier)
                                    .state =
                                newSessions.length - 1;
                          }
                        },
                        minimizedImages: minimizedImages,
                        onImageSelect: (id) {
                          ref
                              .read(floatingImagesProvider.notifier)
                              .toggleMinimize(id);
                        },
                        onImageClose: (id) {
                          ref
                              .read(floatingImagesProvider.notifier)
                              .removeImage(id);
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
                        Icon(
                          Icons.terminal,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No active sessions',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
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
          ),
        ),
      ),
    );
  }

  void _showConnectDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => ConnectionDialog(
        onConnect: (Host host, SshConnectionConfig config) =>
            _connectAndHandleHostKey(context, ref, host, config),
      ),
    );
  }

  /// Opens a bottom sheet listing the current session's port-forward rules
  /// with live status and manual start/stop controls. On mobile, a warning
  /// reminds the user that forwards pause in the background.
  void _showForwardsSheet(BuildContext context, SessionState session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ForwardsSheet(sessionId: session.id),
    );
  }

  /// Attempts a connection; on first contact with an unknown host, prompts
  /// the user (TOFU). Host-key mismatches are reported as errors and never
  /// auto-trusted.
  Future<void> _connectAndHandleHostKey(
    BuildContext context,
    WidgetRef ref,
    Host host,
    SshConnectionConfig config,
  ) async {
    try {
      await ref.read(sessionListProvider.notifier).openSession(host, config);
      final newSessions = ref.read(sessionListProvider);
      ref.read(selectedSessionIndexProvider.notifier).state =
          newSessions.length - 1;
    } on UnknownHostException catch (e) {
      if (!context.mounted) return;
      final trust = await showHostKeyDialog(
        context: context,
        host: e.host,
        port: e.port,
        keyType: e.keyType,
        fingerprintHex: e.fingerprint,
      );
      if (trust != true || !context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection aborted: host not trusted.')),
        );
        return;
      }
      // User accepted — record the fingerprint, then retry the connection.
      // The retry goes through the same verified path; this time verify()
      // returns trusted.
      try {
        // We don't have the raw bytes here (only the hex), so reconstruct.
        final raw = _hexToBytes(e.fingerprint);
        await ref
            .read(knownHostsStoreProvider)
            .trust(e.host, e.port, e.keyType, raw);
      } catch (_) {
        // Best-effort; the retry below will re-prompt if trust didn't persist.
      }
      try {
        await ref.read(sessionListProvider.notifier).openSession(host, config);
        final newSessions = ref.read(sessionListProvider);
        ref.read(selectedSessionIndexProvider.notifier).state =
            newSessions.length - 1;
      } catch (retryError) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connection failed: $retryError')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Connection failed: $e')));
      }
    }
  }
}

class _SessionTabBar extends StatelessWidget {
  final List<SessionState> sessions;
  final int selectedIndex;
  final void Function(int index) onSelect;
  final void Function(String id) onClose;
  final List<FloatingImage> minimizedImages;
  final void Function(String id) onImageSelect;
  final void Function(String id) onImageClose;

  const _SessionTabBar({
    required this.sessions,
    required this.selectedIndex,
    required this.onSelect,
    required this.onClose,
    this.minimizedImages = const [],
    required this.onImageSelect,
    required this.onImageClose,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Session tabs
          for (int index = 0; index < sessions.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => onSelect(index),
                child: Chip(
                  label: Text(
                    sessions[index].host.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: index == selectedIndex
                          ? Colors.white
                          : Colors.white70,
                      fontWeight: index == selectedIndex
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  deleteIcon: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white70,
                  ),
                  onDeleted: () => onClose(sessions[index].id),
                  backgroundColor: index == selectedIndex
                      ? Colors.teal.shade700
                      : sessions[index].reconnecting
                      ? Colors.amber.shade900
                      : sessions[index].connected
                      ? Colors.teal.shade900
                      : Colors.red.shade900,
                  side: index == selectedIndex
                      ? const BorderSide(color: Colors.tealAccent, width: 2)
                      : null,
                ),
              ),
            ),
          // Minimized image tabs
          if (minimizedImages.isNotEmpty)
            Container(
              width: 1,
              color: Colors.white24,
              margin: const EdgeInsets.symmetric(vertical: 8),
            ),
          for (final img in minimizedImages)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => onImageSelect(img.id),
                child: Chip(
                  avatar: Icon(Icons.image, size: 14, color: Colors.white70),
                  label: Text(
                    img.name,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  deleteIcon: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white70,
                  ),
                  onDeleted: () => onImageClose(img.id),
                  backgroundColor: Colors.teal.shade900,
                ),
              ),
            ),
        ],
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
    // Thin session toolbar above the terminal. Only shown when connected so
    // the buttons (e.g. Open SFTP) don't lead somewhere that needs a live
    // SSH session during connecting/reconnecting states.
    return Column(
      children: [
        if (session.connected)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  IconButton(
                    icon: const Icon(Icons.folder_open, size: 18),
                    tooltip: 'Open SFTP',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        context.push('/sftp/${session.id}'),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: TerminalScreen(terminal: session.terminal)),
      ],
    );
  }
}

/// Parses a hex string back into bytes (inverse of session_provider._hex),
/// used to re-feed a fingerprint into KnownHostsStore.trust after the user
/// accepts an unknown host.
Uint8List _hexToBytes(String hex) {
  final out = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(out);
}

class _ForwardsSheet extends ConsumerWidget {
  final String sessionId;
  const _ForwardsSheet({required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref
        .watch(sessionListProvider)
        .where((s) => s.id == sessionId)
        .firstOrNull;
    if (session == null) return const SizedBox.shrink();
    final host = session.host;
    final running = session.runningForwards;
    final notifier = ref.read(sessionListProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!supportsBackgroundForward)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: Colors.amber.shade900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Forwards pause when the app is in the background.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            Text('Port Forwards',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (!session.connected)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Session is not connected. Auto-start forwards will run once it reconnects.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            if (host.forwards.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No forwards configured. Edit the host to add some.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              )
            else
              for (final rule in host.forwards)
                _ForwardRow(
                  rule: rule,
                  running: running[rule.id],
                  canStart: session.connected,
                  onStart: () async {
                    try {
                      await notifier.startForward(sessionId, rule);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    }
                  },
                  onStop: () => notifier.stopForward(sessionId, rule.id),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ForwardRow extends StatelessWidget {
  final ForwardRule rule;
  final ActiveForwardInfo? running;
  final bool canStart;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  const _ForwardRow({
    required this.rule,
    required this.running,
    required this.canStart,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final isRunning = running != null;
    return ListTile(
      leading: Icon(_iconFor(rule.type),
          color: isRunning ? Colors.teal : null),
      title: Text(rule.summary, style: const TextStyle(fontFamily: 'monospace')),
      subtitle: Text(
        isRunning
            ? 'listening on :${running!.boundPort}'
            : rule.autoStart
                ? 'stopped (auto-starts on connect)'
                : 'stopped',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: isRunning
          ? IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Stop',
              onPressed: () {
                onStop();
              },
            )
          : IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Start',
              onPressed: canStart
                  ? () {
                      onStart();
                    }
                  : null,
            ),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  IconData _iconFor(ForwardType type) => switch (type) {
        ForwardType.local => Icons.south_east,
        ForwardType.remote => Icons.north_west,
        ForwardType.socks => Icons.shuffle,
      };
}
