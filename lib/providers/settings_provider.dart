import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

enum KeyboardBarMode {
  auto, // 只在系统键盘弹出时显示
  always, // 始终显示
  hidden, // 始终隐藏
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  return SettingsNotifier();
});

class AppSettings {
  final KeyboardBarMode keyboardBarMode;

  const AppSettings({this.keyboardBarMode = KeyboardBarMode.auto});

  AppSettings copyWith({KeyboardBarMode? keyboardBarMode}) {
    return AppSettings(
      keyboardBarMode: keyboardBarMode ?? this.keyboardBarMode,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  static const _boxName = 'settings';
  static const _keyboardModeKey = 'keyboardBarMode';

  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox(_boxName);
    final modeIndex = box.get(_keyboardModeKey, defaultValue: 0);
    state = AppSettings(keyboardBarMode: KeyboardBarMode.values[modeIndex]);
  }

  Future<void> setKeyboardBarMode(KeyboardBarMode mode) async {
    state = state.copyWith(keyboardBarMode: mode);
    final box = await Hive.openBox(_boxName);
    await box.put(_keyboardModeKey, mode.index);
  }
}
