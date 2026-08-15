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

    testWidgets(
        'truncation indicator updates when streaming pushes past the cap',
        (tester) async {
      // Exactly 500 matches: not truncated, count shows no '+'.
      final terminal = Terminal(maxLines: 10000);
      for (var i = 0; i < 500; i++) {
        terminal.write('foo\r\n');
      }

      await tester.pumpWidget(_wrap(terminal));
      await tester.pump();
      await tester.tap(find.byType(TerminalView));
      await tester.pumpAndSettle();
      await _sendCtrlShiftF(tester);

      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('1/500'), findsOneWidget);

      // One more match beyond the cap: the capped list itself stays
      // identical (the new match is past maxMatches), but the result is now
      // truncated, so the '+' indicator must appear.
      terminal.write('foo\r\n');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('1/500+'), findsOneWidget);
    });

    testWidgets(
        'toggling Match case with an identical result resets to match #1',
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

      // Toggling Match case yields the same match list (all-lowercase
      // content matches both modes), but it is a fresh search: it must
      // restart at match #1, not stay at 2/3.
      await tester.tap(find.byTooltip('Match case'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);
    });

    testWidgets('full scrollback wrap forces a re-search (no early return)',
        (tester) async {
      // Small scrollback so the buffer fills and starts wrapping. Content is
      // periodic (foo/bar) so that, once steady-state is reached, dropping a
      // period from the top and appending the same period at the bottom
      // leaves the match list completely identical — exactly the case where
      // the old early-return kept stale lineIndex snapshots.
      final terminal = Terminal(maxLines: 40);
      for (var i = 0; i < 20; i++) {
        terminal.write('foo\r\nbar\r\n');
      }

      await tester.pumpWidget(_wrap(terminal));
      await tester.pump();
      await tester.tap(find.byType(TerminalView));
      await tester.pumpAndSettle();
      await _sendCtrlShiftF(tester);

      await tester.enterText(find.byType(TextField), 'bar');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('1/20'), findsOneWidget);

      // First wrap write reaches the steady state (20 -> 19 matches).
      terminal.write('bar\r\nfoo\r\n');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('1/19'), findsOneWidget);

      // Snapshot the anchors of a match in the middle of the buffer (on a
      // line that survives further wraps).
      final line5 = terminal.buffer.lines[5];
      final oldAnchors = List.of(line5.anchors);
      expect(oldAnchors.length, 2);

      // Second wrap write: the match list is now completely identical to the
      // previous result, but because the scrollback is full (lines have been
      // dropped from the top) the widget must still re-run the search
      // (dispose + recreate anchors) so the stored lineIndex snapshots used
      // by _scrollToCurrent are refreshed.
      terminal.write('bar\r\nfoo\r\n');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('1/19'), findsOneWidget);
      final newAnchors = terminal.buffer.lines[5].anchors;
      expect(newAnchors.length, oldAnchors.length);
      var recreated = false;
      for (final a in newAnchors) {
        if (!oldAnchors.any((o) => identical(o, a))) recreated = true;
      }
      expect(recreated, isTrue,
          reason:
              'anchors must be recreated after scrollback wrap (re-search ran)');
    });
  });
}
