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

/// Sends Ctrl+Shift+F to whatever currently has primary focus.
Future<void> _sendCtrlShiftF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// Sends bare Ctrl+F (no shift) to whatever currently has primary focus.
Future<void> _sendCtrlF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  group('TerminalWidget search', () {
    testWidgets('Ctrl+Shift+F opens the search bar and Esc closes it',
        (tester) async {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('hello world\nfoo bar\n');

      await tester.pumpWidget(_wrap(terminal));
      await tester.pump();

      // Search bar not visible initially.
      expect(find.byTooltip('Close (Esc)'), findsNothing);

      // Focus the terminal so it receives the key event, then Ctrl+Shift+F.
      await tester.tap(find.byType(TerminalView));
      await tester.pumpAndSettle();
      await _sendCtrlShiftF(tester);

      expect(find.byTooltip('Close (Esc)'), findsOneWidget);
      expect(find.text('Search (Ctrl+Shift+F)'), findsOneWidget);

      // Esc closes it.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close (Esc)'), findsNothing);
    });

    testWidgets('bare Ctrl+F is not intercepted by the search UI',
        (tester) async {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('hello world\nfoo bar\n');

      await tester.pumpWidget(_wrap(terminal));
      await tester.pump();
      await tester.tap(find.byType(TerminalView));
      await tester.pumpAndSettle();

      await _sendCtrlF(tester);
      // The search bar must NOT open: Ctrl+F must reach the shell
      // (readline forward-char, emacs, TUIs).
      expect(find.byTooltip('Close (Esc)'), findsNothing);
      // Let any timer the terminal input handler scheduled fire.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    });

    testWidgets('typing a query reports match count', (tester) async {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('foo\nfoo\nfoo\n');

      await tester.pumpWidget(_wrap(terminal));
      await tester.pump();
      await tester.tap(find.byType(TerminalView));
      await tester.pumpAndSettle();
      await _sendCtrlShiftF(tester);

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
      await _sendCtrlShiftF(tester);

      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);

      await tester.tap(find.byTooltip('Next match'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous match'));
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);
    });

    testWidgets('streaming output preserves the current match',
        (tester) async {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('foo\nfoo\nfoo\n');

      await tester.pumpWidget(_wrap(terminal));
      await tester.pump();
      await tester.tap(find.byType(TerminalView));
      await tester.pumpAndSettle();
      await _sendCtrlShiftF(tester);

      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);

      // Navigate to match 2/3.
      await tester.tap(find.byTooltip('Next match'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);

      // Streaming output triggers the debounced re-search; the current match
      // must be preserved, not reset to 1/3.
      terminal.write('bar\r\n');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets('CellAnchors are disposed when results change (no leak)',
        (tester) async {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('foo\r\nfoo\r\nfoo\r\n');

      int totalAnchors() {
        var n = 0;
        final b = terminal.buffer;
        for (var y = 0; y < b.height; y++) {
          n += b.lines[y].anchors.length;
        }
        return n;
      }

      await tester.pumpWidget(_wrap(terminal));
      await tester.pump();
      await tester.tap(find.byType(TerminalView));
      await tester.pumpAndSettle();
      await _sendCtrlShiftF(tester);

      // First search: 3 matches → 6 anchors (2 per match). Pump past the
      // 150 ms debounce (pumpAndSettle doesn't guarantee advancing the clock
      // far enough to fire the Timer).
      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(totalAnchors(), 6);

      // A second search with no matches must dispose the old anchors,
      // not accumulate them.
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(totalAnchors(), 0);
    });
  });
}
