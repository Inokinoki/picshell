import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:picshell/models/terminal_palette.dart';
import 'package:picshell/providers/settings_provider.dart';
import 'package:picshell/widgets/terminal_widget/terminal_widget.dart';
import 'package:xterm/xterm.dart';

void main() {
  late Directory tempDir;
  late SettingsNotifier notifier;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('picshell_hotswap_');
    Hive.init(tempDir.path);
  });

  setUp(() {
    // Fresh notifier per test so each starts from defaults; Hive is init'd
    // once in setUpAll because it caches the home directory.
    notifier = SettingsNotifier(loadFromStorage: false);
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

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => notifier),
      ],
      child: MaterialApp(
        home: Scaffold(body: TerminalWidget(terminal: Terminal(maxLines: 1000))),
      ),
    );
  }

  testWidgets('TerminalView receives the default theme/style on first build',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.theme.background, TerminalPalette.defaultTheme.theme.background);
    expect(view.textStyle.fontSize, defaultFontSize);
    // Empty fontFamily → xterm platform default ('monospace').
    expect(view.textStyle.fontFamily, 'monospace');
  });

  testWidgets('changing appearance settings hot-swaps the TerminalView params',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    // The setters perform real Hive file I/O; run them outside the widget
    // test's fake-async zone so their Futures can complete, then pump to let
    // the reactive rebuild propagate to TerminalView.
    await tester.runAsync(() async {
      await notifier.setPalette(TerminalPalette.dracula);
      await notifier.setFontFamily('JetBrains Mono');
      await notifier.setFontSize(20);
    });
    await tester.pump();
    await tester.pumpAndSettle();

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(
      view.theme.background,
      TerminalPalette.dracula.theme.background,
      reason: 'palette should hot-swap',
    );
    expect(view.textStyle.fontFamily, 'JetBrains Mono');
    expect(view.textStyle.fontSize, 20);
  });

  testWidgets('selecting a non-default palette changes the foreground too',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.runAsync(() async {
      await notifier.setPalette(TerminalPalette.solarizedLight);
    });
    await tester.pump();
    await tester.pumpAndSettle();

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(
      view.theme.background,
      TerminalPalette.solarizedLight.theme.background,
    );
    expect(
      view.theme.background.computeLuminance(),
      greaterThan(0.5),
      reason: 'solarized light bg should be bright',
    );
  });
}
