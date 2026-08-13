import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/providers/settings_provider.dart';
import 'package:picshell/widgets/terminal_widget/terminal_widget.dart';
import 'package:xterm/xterm.dart';

Widget _wrap(Terminal terminal) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        (ref) => SettingsNotifier(loadFromStorage: false),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: TerminalWidget(terminal: terminal)),
    ),
  );
}

/// Sends Ctrl+F to whatever currently has primary focus.
Future<void> _sendCtrlF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  group('TerminalWidget search', () {
    testWidgets('Ctrl+F opens the search bar and Esc closes it',
        (tester) async {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('hello world\nfoo bar\n');

      await tester.pumpWidget(_wrap(terminal));
      await tester.pump();

      // Search bar not visible initially.
      expect(find.byTooltip('关闭 (Esc)'), findsNothing);

      // Focus the terminal so it receives the key event, then Ctrl+F.
      await tester.tap(find.byType(TerminalView));
      await tester.pumpAndSettle();
      await _sendCtrlF(tester);

      expect(find.byTooltip('关闭 (Esc)'), findsOneWidget);
      expect(find.text('搜索（Ctrl+F）'), findsOneWidget);

      // Esc closes it.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭 (Esc)'), findsNothing);
    });

    testWidgets('typing a query reports match count', (tester) async {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('foo\nfoo\nfoo\n');

      await tester.pumpWidget(_wrap(terminal));
      await tester.pump();
      await tester.tap(find.byType(TerminalView));
      await tester.pumpAndSettle();
      await _sendCtrlF(tester);

      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pumpAndSettle();

      // Current is 1 of 3 matches.
      expect(find.text('1/3'), findsOneWidget);
    });

    testWidgets('next/prev cycle the current match', (tester) async {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('foo\nfoo\nfoo\n');

      await tester.pumpWidget(_wrap(terminal));
      await tester.pump();
      await tester.tap(find.byType(TerminalView));
      await tester.pumpAndSettle();
      await _sendCtrlF(tester);

      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);

      await tester.tap(find.byTooltip('下一个'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);

      await tester.tap(find.byTooltip('上一个'));
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);
    });
  });
}
