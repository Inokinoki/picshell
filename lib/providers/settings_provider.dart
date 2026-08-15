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

  const AppSettings({
    this.keyboardBarMode = KeyboardBarMode.auto,
    this.themeMode = ThemeMode.system,
    this.palette = TerminalPalette.defaultTheme,
    this.fontFamily = defaultFontFamily,
    this.fontSize = defaultFontSize,
    this.lineHeight = defaultLineHeight,
  });

  AppSettings copyWith({
    KeyboardBarMode? keyboardBarMode,
    ThemeMode? themeMode,
    TerminalPalette? palette,
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
  }) {
    return AppSettings(
      keyboardBarMode: keyboardBarMode ?? this.keyboardBarMode,
      themeMode: themeMode ?? this.themeMode,
      palette: palette ?? this.palette,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
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
  static const _minFontSize = 8.0;
  static const _maxFontSize = 28.0;

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
    // persist forever).
    if (fontSize != rawFontSize) {
      await box.put(_fontSizeKey, fontSize);
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
      lineHeight: rawLineHeight is num
          ? rawLineHeight.toDouble()
          : defaultLineHeight,
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
}
