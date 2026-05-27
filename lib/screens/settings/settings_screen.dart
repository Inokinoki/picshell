import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';

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
