import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/session_provider.dart';
import '../../services/local_file_service.dart';
import '../../services/sftp_browser_backend.dart';
import '../../services/sftp_entry.dart';
// sftp_service exports the joinPath/parentPath/sftpErrorMessage helpers and
// the SftpService implementation of the backend.
import '../../services/sftp_service.dart';

/// Full SFTP browser for one session: browse, download, upload, mkdir,
/// rename, delete. Reached via `/sftp/:sessionId`.
///
/// The optional [backend] / [localFiles] parameters let tests inject fakes;
/// in production the screen builds real [SftpService] / [LocalFileService]
/// from the session's [SshService].
class SftpBrowserScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final SftpBrowserBackend? backend;
  final LocalFileService? localFiles;

  const SftpBrowserScreen({
    super.key,
    required this.sessionId,
    this.backend,
    this.localFiles,
  });

  @override
  ConsumerState<SftpBrowserScreen> createState() => _SftpBrowserScreenState();
}

class _SftpBrowserScreenState extends ConsumerState<SftpBrowserScreen> {
  // Null until the backend has been successfully resolved AND used once; all
  // actions guard on this so a failed init can never hit an unusable backend.
  SftpBrowserBackend? _backend;
  // The resolved backend, kept for close() in dispose even if init failed
  // midway (a created SftpService may already hold an SFTP channel).
  SftpBrowserBackend? _resolvedForClose;
  late final LocalFileService _localFiles;
  String _currentPath = '.';
  List<SftpEntry> _entries = [];
  bool _loading = true;
  String? _error;
  // Active transfer progress UI. Null when idle; shown as a slim bottom bar.
  String? _transferLabel;
  double? _transferValue; // null → indeterminate progress

  @override
  void initState() {
    super.initState();
    _localFiles = widget.localFiles ?? LocalFileService();
    _refresh();
  }

  @override
  void dispose() {
    // The screen owns the SftpService it created (and its SFTP channel).
    _resolvedForClose?.close();
    super.dispose();
  }

  /// Resolves the backend exactly once and reuses it for the screen's
  /// lifetime. We can't do it in initState because we need `ref`, and the
  /// session may reconnect later — SftpService itself handles
  /// client-replacement, so a single instance is fine.
  SftpBrowserBackend _resolveBackend() {
    final existing = _resolvedForClose;
    if (existing != null) return existing;
    final injected = widget.backend;
    if (injected != null) {
      _resolvedForClose = injected;
      return injected;
    }
    final session = ref
        .read(sessionListProvider)
        .firstWhere(
          (s) => s.id == widget.sessionId,
          orElse: () => throw StateError('Session not found'),
        );
    final created = SftpService(session.sshService);
    _resolvedForClose = created;
    return created;
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final backend = _resolveBackend();
      // Normalise the starting '.' to an absolute path on first load.
      if (_currentPath == '.') {
        _currentPath = await backend.absolute('.');
      }
      final entries = await backend.listdir(_currentPath);
      if (!mounted) return;
      // Backend is usable; enable actions.
      _backend = backend;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      _backend = null;
      setState(() {
        _error = sftpErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _navigateInto(String name) {
    _currentPath = joinPath(_currentPath, name);
    _refresh();
  }

  void _navigateUp() {
    final parent = parentPath(_currentPath);
    if (parent == _currentPath) return; // already at root
    _currentPath = parent;
    _refresh();
  }

  Future<void> _newFolder() async {
    final backend = _backend;
    if (backend == null) {
      _snack('Not connected');
      return;
    }
    final name = await _promptForText(
      title: 'New Folder',
      label: 'Folder name',
    );
    if (name == null || name.isEmpty) return;
    final nameError = validateEntryName(name);
    if (nameError != null) {
      _snack(nameError);
      return;
    }
    try {
      await backend.mkdir(joinPath(_currentPath, name));
      _refresh();
    } catch (e) {
      _snack(sftpErrorMessage(e));
    }
  }

  Future<void> _upload() async {
    final backend = _backend;
    if (backend == null) {
      _snack('Not connected');
      return;
    }
    final source = await _localFiles.pickUpload();
    if (source == null) return;
    final baseName = source.split(RegExp(r'[/\\]')).last;
    final nameError = validateEntryName(baseName);
    if (nameError != null) {
      _snack(nameError);
      return;
    }
    final remote = joinPath(_currentPath, baseName);
    try {
      // Never silently truncate an existing remote file.
      if (await backend.exists(remote)) {
        final confirmed = await _confirm(
          title: 'Overwrite',
          message: '"$baseName" already exists here. Overwrite it?',
          confirmLabel: 'Overwrite',
        );
        if (confirmed != true) return;
      }
    } catch (_) {
      // Existence check is best-effort; proceed with the upload attempt.
    }
    _startTransfer('Uploading $baseName');
    // The backend reports the file size via onStart, making the bar
    // determinate; onProgress then reports bytes acked by the server.
    int? total;
    try {
      await backend.upload(
        source,
        remote,
        onStart: (t) {
          total = t;
          _updateTransfer(0, t);
        },
        onProgress: (n) => _updateTransfer(n, total),
      );
      _refresh();
      if (mounted) _snack('Uploaded $baseName');
    } catch (e) {
      _snack(sftpErrorMessage(e));
    } finally {
      _endTransfer();
    }
  }

  Future<void> _download(SftpEntry entry) async {
    // Guard before opening the picker so "Not connected" comes first.
    final backend = _backend;
    if (backend == null) {
      _snack('Not connected');
      return;
    }
    final target = await _localFiles.pickDownload(entry.name);
    if (target == null) return;
    final remote = joinPath(_currentPath, entry.name);
    _startTransfer('Downloading ${entry.name}');
    try {
      await backend.download(remote, target, onProgress: (n) {
        _updateTransfer(n, entry.size);
      });
      if (mounted) _snack('Saved to $target');
    } catch (e) {
      _snack('Download failed: ${sftpErrorMessage(e)}');
    } finally {
      _endTransfer();
    }
  }

  /// Shows the slim bottom progress bar with [label] (indeterminate until a
  /// progress event with a known total arrives).
  void _startTransfer(String label) {
    if (!mounted) return;
    setState(() {
      _transferLabel = label;
      _transferValue = null;
    });
  }

  void _updateTransfer(int transferred, int? total) {
    if (!mounted || _transferLabel == null) return;
    setState(() {
      _transferValue = (total != null && total > 0)
          ? (transferred / total).clamp(0.0, 1.0)
          : null;
    });
  }

  void _endTransfer() {
    if (!mounted) return;
    setState(() {
      _transferLabel = null;
      _transferValue = null;
    });
  }

  Future<void> _rename(SftpEntry entry) async {
    final backend = _backend;
    if (backend == null) {
      _snack('Not connected');
      return;
    }
    final newName = await _promptForText(
      title: 'Rename',
      label: 'New name',
      initial: entry.name,
    );
    if (newName == null || newName.isEmpty || newName == entry.name) return;
    final nameError = validateEntryName(newName);
    if (nameError != null) {
      _snack(nameError);
      return;
    }
    try {
      await backend.rename(
        joinPath(_currentPath, entry.name),
        joinPath(_currentPath, newName),
      );
      _refresh();
    } catch (e) {
      _snack(sftpErrorMessage(e));
    }
  }

  Future<void> _delete(SftpEntry entry) async {
    final backend = _backend;
    if (backend == null) {
      _snack('Not connected');
      return;
    }
    final confirmed = await _confirm(
      title: 'Delete',
      message: 'Delete "${entry.name}"?',
    );
    if (confirmed != true) return;
    try {
      final path = joinPath(_currentPath, entry.name);
      if (entry.isDirectory) {
        await backend.rmdir(path);
      } else {
        await backend.remove(path);
      }
      _refresh();
    } catch (e) {
      _snack(sftpErrorMessage(e));
    }
  }

  Future<String?> _promptForText({
    required String title,
    required String label,
    String initial = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _PromptDialog(title: title, label: label, initial: initial),
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    String confirmLabel = 'Delete',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final atRoot = _currentPath == '/';
    final transferLabel = _transferLabel;
    return Scaffold(
      bottomNavigationBar: transferLabel == null
          ? null
          : SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: _transferValue),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            transferLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (_transferValue != null)
                          Text(
                            '${(_transferValue! * 100).round()}%',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_upward),
          tooltip: 'Up',
          onPressed: atRoot ? null : _navigateUp,
        ),
        title: Text(
          _currentPath,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'New Folder',
            // Disabled until the backend is up so a failed init can't be
            // tapped into an uninitialized-backend crash.
            onPressed: _backend == null ? null : _newFolder,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Upload Here',
            onPressed: _backend == null ? null : _upload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _refresh)
          : _entries.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return _EntryTile(
                  entry: entry,
                  onTap: () {
                    if (entry.isDirectory) {
                      _navigateInto(entry.name);
                    } else {
                      _download(entry);
                    }
                  },
                  onRename: () => _rename(entry),
                  onDelete: () => _delete(entry),
                );
              },
            ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final SftpEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _EntryTile({
    required this.entry,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        entry.isDirectory ? Icons.folder : Icons.insert_drive_file,
        color: entry.isDirectory ? Colors.teal : Colors.grey,
      ),
      title: Text(entry.name),
      subtitle: Text(entry.sizeLabel, style: const TextStyle(fontSize: 12)),
      trailing: PopupMenuButton<String>(
        onSelected: (action) {
          switch (action) {
            case 'rename':
              onRename();
              break;
            case 'delete':
              onDelete();
              break;
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Empty folder',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// AlertDialog with a single text field. Owns its TextEditingController so
/// the controller is disposed with the widget (after the route exit
/// animation completes) instead of leaking or being disposed too early.
class _PromptDialog extends StatefulWidget {
  final String title;
  final String label;
  final String initial;

  const _PromptDialog({
    required this.title,
    required this.label,
    this.initial = '',
  });

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
