import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Replays the captured cmd -> powershell transition and checks where the
/// emulator thinks the cursor is when the user starts typing.
void main() {
  test('cursor position after powershell transition matches ConPTY intent',
      () {
    final terminal = Terminal(maxLines: 1000);
    terminal.resize(120, 30);

    final hex =
        File('tool/ps_stream.hex').readAsStringSync();
    final bytes = [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    terminal.write(ascii.decode(bytes));

    final cursorRow = terminal.buffer.cursorY;
    final cursorCol = terminal.buffer.cursorX;
    stdout.writeln('cursor after powershell prompt: row=$cursorRow col=$cursorCol');

    // ConPTY printed the prompt via ESC[10;1H, i.e. row index 9, col 0, then
    // wrote "PS C:\Users\Inoki> " (19 chars) -> cursor col 19.
    expect(cursorRow, 9);
    expect(cursorCol, 19);
  });
}
