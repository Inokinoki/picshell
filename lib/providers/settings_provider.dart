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
  static const _minFontSize = 8.0;
  static const _maxFontSize = 28.0;
  static const _minLineHeight = 1.0;
  static const _maxLineHeight = 2.0;

  /// Public Hive key for the require-biometric flag, so `main()` can read it
  /// before the app (and thus [SettingsNotifier]) is running.
  static const biometricKey = _requireBiometricKey;

  SettingsNotifier({bool loadFromStorage = true}) : super(const AppSettings()) {
    if (loadFromStorage) _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox(_boxName);
    // Corrupted Hive values must not throw (or silently abort the rest of
    // the load): fall back to defaults on any type mismatch.
    T _enum<T extends Enum>(String key, List<T> values, T fallback) {
      final raw = box.get(key);
      if (raw is int) {
        return values[raw.clamp(0, values.length - 1)];
      }
      return fallback;
    }

    final rawFamily = box.get(_fontFamilyKey);
    final rawFontSize = box.get(_fontSizeKey);
    final rawLineHeight = box.get(_lineHeightKey);

    final fontSize = rawFontSize is num
        ? rawFontSize.toDouble().clamp(_minFontSize, _maxFontSize)
        : defaultFontSize;
    // Clamp once at load so state and the persisted value agree (the sliders
    // clamp for display only; a stale out-of-range value would otherwise
    // persist forever). Guarded by the touched flag so the repair write never
    // clobbers a value the user just set while the load was in flight.
    if (fontSize != rawFontSize && !_touchedFontSize) {
      await box.put(_fontSizeKey, fontSize);
    }

    final lineHeight = rawLineHeight is num
        ? rawLineHeight.toDouble().clamp(_minLineHeight, _maxLineHeight)
        : defaultLineHeight;
    // Same load-time clamp + on-disk repair as fontSize above.
    if (lineHeight != rawLineHeight && !_touchedLineHeight) {
      await box.put(_lineHeightKey, lineHeight);
    }

    final loaded = AppSettings(
      keyboardBarMode: _enum(
        _keyboardModeKey,
        KeyboardBarMode.values,
        KeyboardBarMode.auto,
      ),
      themeMode: _enum(_themeModeKey, ThemeMode.values, ThemeMode.system),
      palette: _enum(
        _paletteKey,
        TerminalPalette.values,
        TerminalPalette.defaultTheme,
      ),
      fontFamily: rawFamily is String ? rawFamily : defaultFontFamily,
      fontSize: fontSize,
      lineHeight: lineHeight,
      requireBiometric:
          box.get(_requireBiometricKey) is bool
              ? box.get(_requireBiometricKey) as bool
              : false,
      relockOnBackground:
          box.get(_relockOnBackgroundKey) is bool
              ? box.get(_relockOnBackgroundKey) as bool
              : false,
    );

    // Merge field-by-field: this fire-and-forget load can complete after the
    // user already changed a setting during startup, so only overwrite fields
    // the user has not touched (their setters persisted the new values
    // already).
    state = state.copyWith(
      keyboardBarMode: _touchedKeyboardBarMode
          ? state.keyboardBarMode
          : loaded.keyboardBarMode,
      themeMode: _touchedThemeMode ? state.themeMode : loaded.themeMode,
      palette: _touchedPalette ? state.palette : loaded.palette,
      fontFamily: _touchedFontFamily ? state.fontFamily : loaded.fontFamily,
      fontSize: _touchedFontSize ? state.fontSize : loaded.fontSize,
      lineHeight: _touchedLineHeight ? state.lineHeight : loaded.lineHeight,
    );
  }

  /// Per-field "user already changed this" flags, consulted by [_load] so a
  /// late-completing load never overwrites a user change.
  bool _touchedKeyboardBarMode = false;
  bool _touchedThemeMode = false;
  bool _touchedPalette = false;
  bool _touchedFontFamily = false;
  bool _touchedFontSize = false;
  bool _touchedLineHeight = false;

  Future<void> setKeyboardBarMode(KeyboardBarMode mode) async {
    _touchedKeyboardBarMode = true;
    state = state.copyWith(keyboardBarMode: mode);
    final box = await Hive.openBox(_boxName);
    await box.put(_keyboardModeKey, mode.index);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _touchedThemeMode = true;
    state = state.copyWith(themeMode: mode);
    final box = await Hive.openBox(_boxName);
    await box.put(_themeModeKey, mode.index);
  }

  Future<void> setPalette(TerminalPalette palette) async {
    _touchedPalette = true;
    state = state.copyWith(palette: palette);
    final box = await Hive.openBox(_boxName);
    await box.put(_paletteKey, palette.index);
  }

  Future<void> setFontFamily(String fontFamily) async {
    _touchedFontFamily = true;
    state = state.copyWith(fontFamily: fontFamily);
    final box = await Hive.openBox(_boxName);
    await box.put(_fontFamilyKey, fontFamily);
  }

  Future<void> setFontSize(double fontSize) async {
    _touchedFontSize = true;
    state = state.copyWith(fontSize: fontSize);
    final box = await Hive.openBox(_boxName);
    await box.put(_fontSizeKey, fontSize);
  }

  /// Live-drag preview: updates state (so the UI follows the thumb) without
  /// hitting Hive on every tick. [setFontSize] persists on drag end.
  void previewFontSize(double fontSize) {
    _touchedFontSize = true;
    state = state.copyWith(fontSize: fontSize);
  }

  Future<void> setLineHeight(double lineHeight) async {
    _touchedLineHeight = true;
    state = state.copyWith(lineHeight: lineHeight);
    final box = await Hive.openBox(_boxName);
    await box.put(_lineHeightKey, lineHeight);
  }

  /// Live-drag preview for line height — see [previewFontSize].
  void previewLineHeight(double lineHeight) {
    _touchedLineHeight = true;
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
