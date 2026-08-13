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

  SettingsNotifier({bool loadFromStorage = true}) : super(const AppSettings()) {
    if (loadFromStorage) _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox(_boxName);
    final keyboardIndex = box.get(_keyboardModeKey, defaultValue: 0);
    final themeIndex = box.get(_themeModeKey, defaultValue: 0);
    final paletteIndex = box.get(_paletteKey, defaultValue: 0);
    final storedPalette = TerminalPalette.values[paletteIndex];
    state = AppSettings(
      keyboardBarMode: KeyboardBarMode.values[keyboardIndex],
      themeMode: ThemeMode.values[themeIndex],
      palette: storedPalette,
      fontFamily: box.get(_fontFamilyKey, defaultValue: defaultFontFamily),
      fontSize: box.get(_fontSizeKey, defaultValue: defaultFontSize),
      lineHeight: box.get(_lineHeightKey, defaultValue: defaultLineHeight),
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

  Future<void> setLineHeight(double lineHeight) async {
    state = state.copyWith(lineHeight: lineHeight);
    final box = await Hive.openBox(_boxName);
    await box.put(_lineHeightKey, lineHeight);
  }
}
