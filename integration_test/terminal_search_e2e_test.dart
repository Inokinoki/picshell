import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:picshell/widgets/terminal_widget/terminal_widget.dart';

import 'helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Scrollback search: Ctrl+Shift+F opens, query finds and counts matches, '
      'navigation and closing work', (tester) async {
    final container = await initApp();
    await pumpApp(tester, container);
    final terminal = await connectSession(tester, container);

    // Inject scrollback content locally (search operates on the buffer, so
    // this exercises the feature without depending on remote echo).
    for (int i = 1; i <= 30; i++) {
      terminal.write('MATCHLINE $i — filler filler filler\r\n');
    }
    await tester.pumpAndSettle();

    // Open the search bar with Ctrl+Shift+F on the focused terminal.
    await tester.tap(find.byType(TerminalWidget).first);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Search (Ctrl+Shift+F)'), findsOneWidget,
        reason: 'search bar should open');

    await tester.enterText(
        find.widgetWithText(TextField, 'Search (Ctrl+Shift+F)'), 'MATCHLINE');
    await tester.pumpAndSettle();

    // The match counter renders as "<current>/<total>".
    final counter = find.byWidgetPredicate(
      (w) =>
          w is Text && RegExp(r'^\d+/\d+$').hasMatch(w.data ?? ''),
    );
    expect(counter, findsOneWidget, reason: 'match counter should render');
    final countText = tester.widget<Text>(counter).data!;
    final total = int.parse(countText.split('/')[1]);
    expect(total, 30, reason: 'all 30 injected lines should match');

    // Navigate to the next match (button enables once matches exist).
    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();

    // Close via the toolbar button (Esc routing is focus-dependent in the
    // live binding).
    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pumpAndSettle();
    expect(find.text('Search (Ctrl+Shift+F)'), findsNothing,
        reason: 'search bar should close');

    await teardownSessions(tester, container);
    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
