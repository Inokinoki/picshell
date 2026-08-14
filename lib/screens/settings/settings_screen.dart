import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/host_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vault_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Theme'),
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
          const _SectionHeader(title: 'Virtual Keyboard'),
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
          const _SectionHeader(title: '安全'),
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
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.tealAccent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

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

  Future<void> _toggleRequire(bool value) async {
    if (_busy) return;
    final vault = ref.read(vaultServiceProvider);
    final hostStore = ref.read(hostStoreProvider);

    if (value) {
      final confirmed = await _confirmEnable();
      if (!confirmed || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      if (value) {
        // Enroll a device key and re-encrypt everything under it, immediately.
        final key = await vault.getMasterKey();
        await hostStore.reEncryptAll(key);
        await ref.read(settingsProvider.notifier).setRequireBiometric(true);
      } else {
        // Restore plaintext so credentials stay readable without the key,
        // then drop the now-orphaned device key for symmetry.
        await hostStore.reEncryptAll('');
        await ref.read(settingsProvider.notifier).setRequireBiometric(false);
        await vault.unenroll();
      }
    } finally {
      // Never leave the toggle stuck busy / half-flipped on an error.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmEnable() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('启用生物识别加密'),
            content: const Text(
              '已保存的密码和私钥将用设备绑定的密钥加密，每次启动需 Face ID / 指纹解锁。\n\n'
              '注意：卸载 App 或重置设备会丢失该密钥，已加密的密码将无法恢复'
              '（连接信息仍可查看）。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('启用'),
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

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: const Text('启动需生物识别'),
          subtitle: Text(
            checking
                ? '检测设备能力…'
                : available
                    ? '用 Face ID / 指纹加密并解锁凭据'
                    : '此设备不支持生物识别',
          ),
          value: settings.requireBiometric && available,
          onChanged: (!available || _busy) ? null : _toggleRequire,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.lock_clock),
          title: const Text('后台返回重新锁定'),
          subtitle: const Text('App 切回前台时重新要求解锁'),
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
