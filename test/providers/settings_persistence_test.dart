import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
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

  test(
    'persisted appearance settings are reloaded by a new notifier',
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
    },
  );

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

  test(
    'corrupted out-of-range enum index falls back instead of throwing',
    () async {
      // Simulate a corrupted / future-versioned palette index.
      final box = await Hive.openBox('settings');
      await box.put('palette', 9999);
      await box.put('themeMode', -1);

      final n = SettingsNotifier(loadFromStorage: true);
      await _waitFor(
        () =>
            !identical(n.state, const AppSettings()) ||
            n.state.palette == TerminalPalette.values.last,
      );

      // Clamped to the last / first valid values — no RangeError.
      expect(
        n.state.palette,
        TerminalPalette.values.last,
        reason: 'palette clamp',
      );
      expect(
        n.state.themeMode,
        ThemeMode.values.first,
        reason: 'themeMode clamp',
      );
    },
  );

  test(
    'corrupted wrong-type values fall back to defaults without throwing',
    () async {
      final box = await Hive.openBox('settings');
      await box.put('palette', 'nord'); // string instead of int
      await box.put('themeMode', true); // bool instead of int
      await box.put('fontFamily', 42); // int instead of string
      await box.put('fontSize', 'huge'); // string instead of num
      await box.put('lineHeight', [1.5]); // list instead of num

      final n = SettingsNotifier(loadFromStorage: true);
      // _load must complete despite the bad types: wait for it by driving the
      // event loop, then assert defaults (a throw would leave state untouched
      // partway, so also give the load a moment via a completed future).
      await _waitFor(() => !identical(n.state, const AppSettings()));
      await Future<void>.delayed(Duration.zero);

      expect(n.state.palette, TerminalPalette.defaultTheme);
      expect(n.state.themeMode, ThemeMode.system);
      expect(n.state.fontFamily, defaultFontFamily);
      expect(n.state.fontSize, defaultFontSize);
      expect(n.state.lineHeight, defaultLineHeight);
    },
  );

  test('out-of-range persisted fontSize is clamped once at load', () async {
    final box = await Hive.openBox('settings');
    await box.put('fontSize', 99.0);

    final n = SettingsNotifier(loadFromStorage: true);
    await _waitFor(() => n.state.fontSize != defaultFontSize);

    expect(n.state.fontSize, 28.0);
    // State and disk agree after the repair.
    expect(box.get('fontSize') as double, 28.0);
  });

  test('user change made before load completes is not clobbered', () async {
    // Persisted values that differ from both the defaults and the user's
    // in-flight change.
    final box = await Hive.openBox('settings');
    await box.put('palette', TerminalPalette.nord.index);
    await box.put('fontSize', 15.0);

    final n = SettingsNotifier(loadFromStorage: true);
    // The fire-and-forget _load is still awaiting Hive.openBox; the user
    // changes palette before it lands.
    n.setPalette(TerminalPalette.dracula);
    await _waitFor(() => n.state.fontSize == 15.0);

    // User-touched field keeps their value; untouched fields pick up the
    // persisted ones.
    expect(
      n.state.palette,
      TerminalPalette.dracula,
      reason: 'user change must survive the late load',
    );
    expect(n.state.fontSize, 15.0, reason: 'persisted value applies');
    // The user's change won the palette race on disk too.
    expect(box.get('palette'), TerminalPalette.dracula.index);
  });

  test('out-of-range persisted lineHeight is clamped once at load', () async {
    final box = await Hive.openBox('settings');
    await box.put('lineHeight', 47.0);

    final n = SettingsNotifier(loadFromStorage: true);
    await _waitFor(() => n.state.lineHeight != defaultLineHeight);

    expect(n.state.lineHeight, 2.0);
    // State and disk agree after the repair.
    expect(box.get('lineHeight') as double, 2.0);
  });

  test('in-range persisted lineHeight below the minimum is clamped too', () async {
    final box = await Hive.openBox('settings');
    await box.put('lineHeight', 0.0);

    final n = SettingsNotifier(loadFromStorage: true);
    await _waitFor(() => n.state.lineHeight != defaultLineHeight);

    expect(n.state.lineHeight, 1.0);
    expect(box.get('lineHeight') as double, 1.0);
  });

  test('fontSize repair write does not clobber an in-flight user change', () async {
    final box = await Hive.openBox('settings');
    await box.put('fontSize', 99.0); // out-of-range: triggers a repair write

    final n = SettingsNotifier(loadFromStorage: true);
    // The fire-and-forget _load is still pending; the user sets a fresh
    // (in-range) font size before the load's repair write lands.
    n.setFontSize(11.0);
    await _waitFor(() => box.get('fontSize') != null);
    // Let any stray queued writes flush before asserting.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // The user's fresh value survived on disk (the repair was suppressed).
    expect(n.state.fontSize, 11.0);
    expect(box.get('fontSize') as double, 11.0);
  });

  test('lineHeight repair write does not clobber an in-flight user change', () async {
    final box = await Hive.openBox('settings');
    await box.put('lineHeight', 47.0); // out-of-range: triggers a repair write

    final n = SettingsNotifier(loadFromStorage: true);
    n.setLineHeight(1.5);
    await _waitFor(() => box.get('lineHeight') != null);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(n.state.lineHeight, 1.5);
    expect(box.get('lineHeight') as double, 1.5);
  });
}
