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
  late SftpBrowserBackend _backend;
  late final LocalFileService _localFiles;
  String _currentPath = '.';
  List<SftpEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _localFiles = widget.localFiles ?? LocalFileService();
    _refresh();
  }

  /// Builds the production backend lazily on first use. We can't do it in
  /// initState because we need `ref`, and the session may reconnect later —
  /// SftpService itself handles client-replacement, so a single instance is
  /// fine for the screen's lifetime.
  SftpBrowserBackend _resolveBackend() {
    final injected = widget.backend;
    if (injected != null) return injected;
    final session = ref.read(sessionListProvider).firstWhere(
          (s) => s.id == widget.sessionId,
          orElse: () => throw StateError('Session not found'),
        );
    return SftpService(session.sshService);
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _backend = _resolveBackend();
      // Normalise the starting '.' to an absolute path on first load.
      if (_currentPath == '.') {
        _currentPath = await _backend.absolute('.');
      }
      final entries = await _backend.listdir(_currentPath);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
    final name = await _promptForText(
      title: 'New Folder',
      label: 'Folder name',
    );
    if (name == null || name.isEmpty) return;
    try {
      await _backend.mkdir(joinPath(_currentPath, name));
      _refresh();
    } catch (e) {
      _snack(sftpErrorMessage(e));
    }
  }

  Future<void> _upload() async {
    final source = await _localFiles.pickUpload();
    if (source == null) return;
    final baseName = source.split(RegExp(r'[/\\]')).last;
    final remote = joinPath(_currentPath, baseName);
    _snack('Uploading $baseName…');
    try {
      await _backend.upload(source, remote);
      _refresh();
      if (mounted) _snack('Uploaded $baseName');
    } catch (e) {
      _snack('Upload failed: ${sftpErrorMessage(e)}');
    }
  }

  Future<void> _download(SftpEntry entry) async {
    final target = await _localFiles.pickDownload(entry.name);
    if (target == null) return;
    final remote = joinPath(_currentPath, entry.name);
    _snack('Downloading ${entry.name}…');
    try {
      await _backend.download(remote, target);
      if (mounted) _snack('Saved to $target');
    } catch (e) {
      _snack('Download failed: ${sftpErrorMessage(e)}');
    }
  }

  Future<void> _rename(SftpEntry entry) async {
    final newName = await _promptForText(
      title: 'Rename',
      label: 'New name',
      initial: entry.name,
    );
    if (newName == null || newName.isEmpty || newName == entry.name) return;
    try {
      await _backend.rename(
        joinPath(_currentPath, entry.name),
        joinPath(_currentPath, newName),
      );
      _refresh();
    } catch (e) {
      _snack(sftpErrorMessage(e));
    }
  }

  Future<void> _delete(SftpEntry entry) async {
    final confirmed = await _confirm(
      title: 'Delete',
      message: 'Delete "${entry.name}"?',
    );
    if (confirmed != true) return;
    try {
      final path = joinPath(_currentPath, entry.name);
      if (entry.isDirectory) {
        await _backend.rmdir(path);
      } else {
        await _backend.remove(path);
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
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirm({required String title, required String message}) {
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final atRoot = _currentPath == '/';
    return Scaffold(
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
            onPressed: _newFolder,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Upload Here',
            onPressed: _upload,
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
          Icon(Icons.folder_open,
              size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Empty folder',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
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
          Icon(Icons.error_outline,
              size: 64, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
