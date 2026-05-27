import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

enum KeyboardBarMode { auto, always, hidden }

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  return SettingsNotifier();
});

class AppSettings {
  final KeyboardBarMode keyboardBarMode;
  final ThemeMode themeMode;

  const AppSettings({
    this.keyboardBarMode = KeyboardBarMode.auto,
    this.themeMode = ThemeMode.system,
  });

  AppSettings copyWith({
    KeyboardBarMode? keyboardBarMode,
    ThemeMode? themeMode,
  }) {
    return AppSettings(
      keyboardBarMode: keyboardBarMode ?? this.keyboardBarMode,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  static const _boxName = 'settings';
  static const _keyboardModeKey = 'keyboardBarMode';
  static const _themeModeKey = 'themeMode';

  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox(_boxName);
    final keyboardIndex = box.get(_keyboardModeKey, defaultValue: 0);
    final themeIndex = box.get(_themeModeKey, defaultValue: 0);
    state = AppSettings(
      keyboardBarMode: KeyboardBarMode.values[keyboardIndex],
      themeMode: ThemeMode.values[themeIndex],
    );
  }

  Future<void> setKeyboardBarMode(KeyboardBarMode mode) async {
    state = state.copyWith(keyboardBarMode: mode);
    final box = await Hive.openBox(_boxName);
    await box.put(_keyboardModeKey, mode.index);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final box = await Hive.openBox(_boxName);
    await box.put(_themeModeKey, mode.index);
  }
}
