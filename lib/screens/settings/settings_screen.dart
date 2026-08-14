import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../services/platform_capabilities.dart';
import '../../services/ssh_config_import_service.dart';
import 'appearance_section.dart';
import 'widgets/section_header.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SectionHeader(title: 'Theme'),
          _buildThemeModeTile(
            context,
            ref,
            'System',
            'Follow system setting',
            Icons.brightness_auto,
            ThemeMode.system,
            settings.themeMode,
          ),
          _buildThemeModeTile(
            context,
            ref,
            'Light',
            'Light theme',
            Icons.light_mode,
            ThemeMode.light,
            settings.themeMode,
          ),
          _buildThemeModeTile(
            context,
            ref,
            'Dark',
            'Dark theme',
            Icons.dark_mode,
            ThemeMode.dark,
            settings.themeMode,
          ),
          const Divider(),
          const SectionHeader(title: 'Terminal Appearance'),
          const AppearanceSection(),
          const Divider(),
          const SectionHeader(title: 'Virtual Keyboard'),
          _buildKeyboardModeTile(
            context,
            ref,
            'Auto',
            'Show when system keyboard is open',
            Icons.keyboard,
            KeyboardBarMode.auto,
            settings.keyboardBarMode,
          ),
          _buildKeyboardModeTile(
            context,
            ref,
            'Always Show',
            'Always visible below terminal',
            Icons.keyboard_alt,
            KeyboardBarMode.always,
            settings.keyboardBarMode,
          ),
          _buildKeyboardModeTile(
            context,
            ref,
            'Hidden',
            'Never show virtual keyboard',
            Icons.keyboard_hide,
            KeyboardBarMode.hidden,
            settings.keyboardBarMode,
          ),
          const Divider(),
          const _SectionHeader(title: 'SSH'),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Import from ~/.ssh/config'),
            subtitle: Text(canReadSystemSshConfig
                ? 'Auto-discover, pick a file, or paste text'
                : 'Pick a config file or paste its text'),
            onTap: () {
              _startImport(context, ref);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThemeModeTile(
    BuildContext context,
    WidgetRef ref,
    String title,
    String subtitle,
    IconData icon,
    ThemeMode mode,
    ThemeMode currentMode,
  ) {
    final isSelected = currentMode == mode;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.tealAccent : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.tealAccent)
          : const Icon(Icons.circle_outlined, color: Colors.grey),
      onTap: () {
        ref.read(settingsProvider.notifier).setThemeMode(mode);
      },
    );
  }

  Widget _buildKeyboardModeTile(
    BuildContext context,
    WidgetRef ref,
    String title,
    String subtitle,
    IconData icon,
    KeyboardBarMode mode,
    KeyboardBarMode currentMode,
  ) {
    final isSelected = currentMode == mode;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.tealAccent : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.tealAccent)
          : const Icon(Icons.circle_outlined, color: Colors.grey),
      onTap: () {
        ref.read(settingsProvider.notifier).setKeyboardBarMode(mode);
      },
    );
  }

  /// Prompts the user for an import source, reads the config text, and writes
  /// the parsed hosts into the store. Source options adapt to the platform:
  /// auto-discover is only offered where `~/.ssh/config` is reachable.
  Future<void> _startImport(BuildContext context, WidgetRef ref) async {
    final source = await showDialog<_ImportSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Import SSH config'),
        children: [
          if (canReadSystemSshConfig)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, _ImportSource.autoDiscover),
              child: const ListTile(
                leading: Icon(Icons.auto_awesome),
                title: Text('Auto-discover ~/.ssh/config'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _ImportSource.chooseFile),
            child: const ListTile(
              leading: Icon(Icons.folder_open),
              title: Text('Choose file...'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _ImportSource.paste),
            child: const ListTile(
              leading: Icon(Icons.content_paste),
              title: Text('Paste config text...'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
    if (source == null || !context.mounted) return;

    final text = await _readSourceText(context, source);
    if (text == null || text.isEmpty || !context.mounted) return;

    final summary = await SshConfigImportService.importText(text, ref);
    if (!context.mounted) return;
    final msg = summary.skipped > 0
        ? 'Imported ${summary.imported} host(s), skipped ${summary.skipped} duplicate(s).'
        : 'Imported ${summary.imported} host(s).';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Resolves the chosen [source] to config text, or null on cancel/error.
  /// Errors surface as Snackbars so the user can retry with another source.
  Future<String?> _readSourceText(
    BuildContext context,
    _ImportSource source,
  ) async {
    switch (source) {
      case _ImportSource.autoDiscover:
        final path = sshConfigDefaultPath;
        if (path == null) return null;
        try {
          return await File(path).readAsString();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not read $path: $e')),
            );
          }
          return null;
        }
      case _ImportSource.chooseFile:
        final result = await FilePicker.platform.pickFiles(type: FileType.any);
        if (result == null || result.files.isEmpty) return null;
        final path = result.files.first.path;
        if (path == null) return null;
        try {
          return await File(path).readAsString();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not read file: $e')),
            );
          }
          return null;
        }
      case _ImportSource.paste:
        if (!context.mounted) return null;
        return _pasteConfigDialog(context);
    }
  }

  Future<String?> _pasteConfigDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste SSH config'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'Host my-server\n  HostName 10.0.0.1\n  ...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
}

enum _ImportSource { autoDiscover, chooseFile, paste }
