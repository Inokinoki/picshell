import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:picshell/models/terminal_palette.dart';
import 'package:picshell/providers/settings_provider.dart';

/// Waits for [condition] to become true, polling on the microtask queue.
/// SettingsNotifier._load is fire-and-forget in the constructor, so a freshly
/// constructed notifier needs a tick before its state reflects persisted data.
Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future.delayed(const Duration(milliseconds: 5));
  }
  throw TimeoutException('condition was not met within $timeout');
}

/// Hive caches its home directory on the first [Hive.init] call, so the path
/// is established once for the whole suite (setUpAll) rather than per-test;
/// between tests we wipe the 'settings' box so each starts from defaults.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('picshell_settings_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    if (Hive.isBoxOpen('settings')) {
      await Hive.box('settings').deleteFromDisk();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('persisted appearance settings are reloaded by a new notifier',
      () async {
    final a = SettingsNotifier(loadFromStorage: false);
    await a.setPalette(TerminalPalette.nord);
    await a.setFontFamily('JetBrains Mono');
    await a.setFontSize(15.0);
    await a.setLineHeight(1.4);

    final b = SettingsNotifier(loadFromStorage: true);
    await _waitFor(() => b.state.palette == TerminalPalette.nord);

    expect(b.state.palette, TerminalPalette.nord);
    expect(b.state.fontFamily, 'JetBrains Mono');
    expect(b.state.fontSize, 15.0);
    expect(b.state.lineHeight, 1.4);
  });

  test('defaults are applied when nothing is stored', () async {
    final n = SettingsNotifier(loadFromStorage: true);
    await _waitFor(() => n.state.palette == TerminalPalette.defaultTheme);

    expect(n.state.palette, TerminalPalette.defaultTheme);
    expect(n.state.fontFamily, defaultFontFamily);
    expect(n.state.fontSize, defaultFontSize);
    expect(n.state.lineHeight, defaultLineHeight);
  });

  test('copyWith preserves unmentioned fields', () {
    const base = AppSettings(
      palette: TerminalPalette.dracula,
      fontFamily: 'Menlo',
      fontSize: 11,
      lineHeight: 1.5,
    );
    final changed = base.copyWith(fontSize: 20);
    expect(changed.palette, TerminalPalette.dracula);
    expect(changed.fontFamily, 'Menlo');
    expect(changed.fontSize, 20);
    expect(changed.lineHeight, 1.5);
  });
}
