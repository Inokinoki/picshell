import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// The TerminalView must resize the terminal away from its 80x24 default to
/// match the available box — a stuck default geometry makes the remote pty
/// and the local view disagree (mispositioned output, partial clears).
void main() {
  testWidgets('TerminalView resizes terminal to the box', (tester) async {
    final terminal = Terminal(maxLines: 1000);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 600,
          child: TerminalView(terminal),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(terminal.viewHeight, greaterThan(24),
        reason: 'view=${terminal.viewWidth}x${terminal.viewHeight}');
  });
}
