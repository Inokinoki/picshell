import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/host_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vault_provider.dart';
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
          const SectionHeader(title: 'SSH'),
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
          const Divider(),
          const SectionHeader(title: 'Security'),
          const _SecuritySection(),
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

/// Biometric vault toggles. Enabling encrypts all saved passwords/private keys
/// with a device-bound key released by Face ID / Touch ID at launch; disabling
/// re-writes them as plaintext. The require toggle is disabled on devices
/// without biometrics — without a launch gate the key cannot protect anything,
/// and encrypting would make credentials unreadable on the next launch.
class _SecuritySection extends ConsumerStatefulWidget {
  const _SecuritySection();

  @override
  ConsumerState<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<_SecuritySection> {
  bool? _available; // null while the capability check is in flight
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    final vault = ref.read(vaultServiceProvider);
    final ok = await vault.canAuthenticate;
    if (mounted) setState(() => _available = ok);
  }

  /// Flips the vault on/off. Both directions require a successful user
  /// verification (`vault.authenticate()`) — whoever is holding the unlocked
  /// app must prove they own it before encryption is disabled (which would
  /// otherwise expose every secret as plaintext) or re-keyed.
  Future<void> _toggleRequire(bool value) async {
    if (_busy) return;
    final vault = ref.read(vaultServiceProvider);
    final hostStore = ref.read(hostStoreProvider);

    if (value) {
      final confirmed = await _confirmEnable();
      if (!confirmed || !mounted) return;
    }
    // Verify the user before changing the vault state, in either direction.
    final authenticated = await vault.authenticate(
      reason: value
          ? 'Enable biometric encryption for saved credentials'
          : 'Disable biometric encryption for saved credentials',
    );
    if (!authenticated || !mounted) return;
    setState(() => _busy = true);
    String? error;
    try {
      if (value) {
        // Crash-safe enable ordering:
        // 1. Enroll the device key (idempotent).
        // 2. Persist requireBiometric=true.
        // 3. reEncryptAll(key).
        // The flag is set BEFORE re-encryption so that a crash at any point
        // leaves a recoverable state: if we crash after the flag is persisted
        // but before/during re-encryption, the data is still plaintext and the
        // key is enrolled — the next launch prompts for biometrics, releases
        // the enrolled key (plaintext records pass through the cipher
        // unchanged), and a retry of the enable succeeds. The inverse ordering
        // (re-encrypt first, flag last) could crash between the two steps,
        // leaving encrypted data with the flag off; the next launch would then
        // start with an empty passphrase and a re-enable would hard-fail on
        // every marked record — a permanent lockout. On failure (step 3
        // throws) the flag is rolled back below so the persisted state always
        // matches the on-disk encryption state.
        final key = await vault.getMasterKey();
        await ref.read(settingsProvider.notifier).setRequireBiometric(true);
        await hostStore.reEncryptAll(key);
      } else {
        // Disable ordering: decrypt first, then drop the flag, then the key.
        // A crash between any two steps stays recoverable: plaintext data
        // with the flag still on just prompts at launch and passes through.
        await hostStore.reEncryptAll('');
        await ref.read(settingsProvider.notifier).setRequireBiometric(false);
        await vault.unenroll();
      }
    } catch (e) {
      if (value) {
        // Roll the flag back so persisted settings match the (unchanged)
        // on-disk encryption state. reEncryptAll itself already restored the
        // in-memory cipher on failure.
        var rollbackFailed = false;
        try {
          await ref.read(settingsProvider.notifier).setRequireBiometric(false);
        } catch (rollbackError) {
          // Never silently swallow this: a failed rollback leaves the flag on
          // with plaintext data — the exact state the crash-safe ordering
          // exists to avoid. Log it and tell the user; the launch path will
          // also attempt an automatic repair on the next verified unlock.
          rollbackFailed = true;
          debugPrint('requireBiometric rollback failed: $rollbackError');
        }
        if (rollbackFailed) {
          error = 'Failed to enable biometric encryption'
              '${e is StateError ? '' : ': $e'}. '
              'Your saved credentials were not changed. '
              'Warning: the require-biometric setting could NOT be rolled '
              'back, so it may no longer match the stored data — retry the '
              'toggle or the next unlock will attempt to finish the '
              'encryption automatically.';
        }
      }
      error ??= 'Failed to ${value ? 'enable' : 'disable'} biometric encryption'
          '${e is StateError ? '' : ': $e'}. '
          'Your saved credentials were not changed.';
    } finally {
      // Never leave the toggle stuck busy / half-flipped on an error.
      if (mounted) setState(() => _busy = false);
    }
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<bool> _confirmEnable() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Enable biometric encryption'),
            content: const Text(
              'Saved passwords and private keys will be encrypted with a '
              'device-bound key, unlocked by your biometric or device '
              'passcode at launch.\n\n'
              'Note: uninstalling the app or resetting the device loses that '
              'key — encrypted passwords cannot be recovered (connection '
              'details remain viewable).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enable'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final available = _available ?? false;
    final checking = _available == null;
    // The toggle reflects the persisted vault state honestly: if the vault is
    // armed (requireBiometric=true) it shows ON even when biometrics are
    // currently unavailable — showing OFF would let the user believe the
    // vault is disabled while data on disk is still governed by the flag.
    final armedButUnavailable = settings.requireBiometric && !available && !checking;

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: const Text('Require biometric unlock'),
          subtitle: Text(
            checking
                ? 'Checking device capability…'
                : armedButUnavailable
                    ? 'Encryption is ON but biometrics are unavailable on '
                      'this device. At launch the device passcode is used as '
                      'fallback; if that also fails, credentials unlock with '
                      'a visible warning.'
                    : available
                        ? 'Encrypt credentials; unlock with biometrics or '
                          'device passcode'
                        : 'Biometrics not supported on this device',
          ),
          value: settings.requireBiometric,
          onChanged: (!available || _busy) ? null : _toggleRequire,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.lock_clock),
          title: const Text('Re-lock on background'),
          subtitle: const Text('Require unlock again when returning to the app'),
          value: settings.relockOnBackground,
          onChanged: (!settings.requireBiometric)
              ? null
              : (v) =>
                  ref.read(settingsProvider.notifier).setRelockOnBackground(v),
        ),
      ],
    );
  }
}
