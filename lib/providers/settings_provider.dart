import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/terminal_palette.dart';

enum KeyboardBarMode { auto, always, hidden }

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  return SettingsNotifier();
});

/// Sentinel font family meaning "use the terminal renderer's platform
/// default" (the xterm fallback chain). Stored as the empty string so it is
/// distinguishable from a real family name like 'JetBrains Mono'.
const defaultFontFamily = '';

const defaultFontSize = 13.0;
const defaultLineHeight = 1.2;

class AppSettings {
  final KeyboardBarMode keyboardBarMode;
  final ThemeMode themeMode;
  final TerminalPalette palette;
  final String fontFamily;
  final double fontSize;
  final double lineHeight;

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
    this.palette = TerminalPalette.defaultTheme,
    this.fontFamily = defaultFontFamily,
    this.fontSize = defaultFontSize,
    this.lineHeight = defaultLineHeight,
    this.requireBiometric = false,
    this.relockOnBackground = false,
  });

  AppSettings copyWith({
    KeyboardBarMode? keyboardBarMode,
    ThemeMode? themeMode,
    TerminalPalette? palette,
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    bool? requireBiometric,
    bool? relockOnBackground,
  }) {
    return AppSettings(
      keyboardBarMode: keyboardBarMode ?? this.keyboardBarMode,
      themeMode: themeMode ?? this.themeMode,
      palette: palette ?? this.palette,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      requireBiometric: requireBiometric ?? this.requireBiometric,
      relockOnBackground: relockOnBackground ?? this.relockOnBackground,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  static const _boxName = 'settings';
  static const _keyboardModeKey = 'keyboardBarMode';
  static const _themeModeKey = 'themeMode';
  static const _paletteKey = 'palette';
  static const _fontFamilyKey = 'fontFamily';
  static const _fontSizeKey = 'fontSize';
  static const _lineHeightKey = 'lineHeight';
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
    // Clamp enum indices: a corrupted or future-versioned box value would
    // otherwise throw RangeError out of this fire-and-forget _load.
    T _enum<T extends Enum>(String key, List<T> values) {
      final index = box.get(key, defaultValue: 0) as int;
      return values[index.clamp(0, values.length - 1)];
    }

    state = AppSettings(
      keyboardBarMode: _enum(_keyboardModeKey, KeyboardBarMode.values),
      themeMode: _enum(_themeModeKey, ThemeMode.values),
      palette: _enum(_paletteKey, TerminalPalette.values),
      fontFamily: box.get(_fontFamilyKey, defaultValue: defaultFontFamily),
      fontSize: box.get(_fontSizeKey, defaultValue: defaultFontSize),
      lineHeight: box.get(_lineHeightKey, defaultValue: defaultLineHeight),
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

  Future<void> setPalette(TerminalPalette palette) async {
    state = state.copyWith(palette: palette);
    final box = await Hive.openBox(_boxName);
    await box.put(_paletteKey, palette.index);
  }

  Future<void> setFontFamily(String fontFamily) async {
    state = state.copyWith(fontFamily: fontFamily);
    final box = await Hive.openBox(_boxName);
    await box.put(_fontFamilyKey, fontFamily);
  }

  Future<void> setFontSize(double fontSize) async {
    state = state.copyWith(fontSize: fontSize);
    final box = await Hive.openBox(_boxName);
    await box.put(_fontSizeKey, fontSize);
  }

  /// Live-drag preview: updates state (so the UI follows the thumb) without
  /// hitting Hive on every tick. [setFontSize] persists on drag end.
  void previewFontSize(double fontSize) {
    state = state.copyWith(fontSize: fontSize);
  }

  Future<void> setLineHeight(double lineHeight) async {
    state = state.copyWith(lineHeight: lineHeight);
    final box = await Hive.openBox(_boxName);
    await box.put(_lineHeightKey, lineHeight);
  }

  /// Live-drag preview for line height — see [previewFontSize].
  void previewLineHeight(double lineHeight) {
    state = state.copyWith(lineHeight: lineHeight);
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
