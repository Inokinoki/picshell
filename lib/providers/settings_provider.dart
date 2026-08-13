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

  /// Require biometric (FaceID/TouchID) unlock before the app is usable. When
  /// enabled, saved passwords/private keys are encrypted at rest with a
  /// device-bound key released only after a successful biometric prompt.
  final bool requireBiometric;

  /// Re-show the lock screen when the app returns from background. The
  /// in-memory key is NOT cleared (a known v1 limitation), so this is a
  /// UI-gate rather than a full re-encryption.
  final bool relockOnBackground;

  const AppSettings({
    this.keyboardBarMode = KeyboardBarMode.auto,
    this.themeMode = ThemeMode.system,
    this.requireBiometric = false,
    this.relockOnBackground = false,
  });

  AppSettings copyWith({
    KeyboardBarMode? keyboardBarMode,
    ThemeMode? themeMode,
    bool? requireBiometric,
    bool? relockOnBackground,
  }) {
    return AppSettings(
      keyboardBarMode: keyboardBarMode ?? this.keyboardBarMode,
      themeMode: themeMode ?? this.themeMode,
      requireBiometric: requireBiometric ?? this.requireBiometric,
      relockOnBackground: relockOnBackground ?? this.relockOnBackground,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  static const _boxName = 'settings';
  static const _keyboardModeKey = 'keyboardBarMode';
  static const _themeModeKey = 'themeMode';
  static const _requireBiometricKey = 'requireBiometric';
  static const _relockOnBackgroundKey = 'relockOnBackground';

  /// Public Hive key for the require-biometric flag, so `main()` can read it
  /// before the app (and thus [SettingsNotifier]) is running.
  static const biometricKey = _requireBiometricKey;

  SettingsNotifier({bool loadFromStorage = true}) : super(const AppSettings()) {
    if (loadFromStorage) _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox(_boxName);
    final keyboardIndex = box.get(_keyboardModeKey, defaultValue: 0);
    final themeIndex = box.get(_themeModeKey, defaultValue: 0);
    state = AppSettings(
      keyboardBarMode: KeyboardBarMode.values[keyboardIndex],
      themeMode: ThemeMode.values[themeIndex],
      requireBiometric: box.get(_requireBiometricKey, defaultValue: false),
      relockOnBackground: box.get(_relockOnBackgroundKey, defaultValue: false),
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

  Future<void> setRequireBiometric(bool value) async {
    state = state.copyWith(requireBiometric: value);
    final box = await Hive.openBox(_boxName);
    await box.put(_requireBiometricKey, value);
  }

  Future<void> setRelockOnBackground(bool value) async {
    state = state.copyWith(relockOnBackground: value);
    final box = await Hive.openBox(_boxName);
    await box.put(_relockOnBackgroundKey, value);
  }
}
