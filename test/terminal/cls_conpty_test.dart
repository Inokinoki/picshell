import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Reproduces the exact byte stream Windows OpenSSH (ConPTY) sends when the
/// user runs `cls`, captured from a real session (tool/cls_stream.hex).
/// After it, the live screen must be empty except the fresh prompt.
void main() {
  test('ConPTY cls stream clears the live screen', () {
    final terminal = Terminal(maxLines: 1000);

    // Fill the screen with content like a `dir` listing would.
    for (var i = 0; i < 40; i++) {
      terminal.write('2026/02/14  23:44    some file $i\r\n');
    }
    terminal.write('inoki@INOKI-ADESKTOP C:\\Users\\Inoki>');

    final hex = File('tool/cls_stream.hex').readAsStringSync();
    final bytes = [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    terminal.write(ascii.decode(bytes));

    // Inspect the live screen rows.
    final nonEmptyRows = <int>[];
    for (var i = 0; i < terminal.viewHeight; i++) {
      final text = terminal.buffer.lines[i].toString();
      if (text.trim().isNotEmpty) nonEmptyRows.add(i);
    }

    // Everything must be erased except the fresh prompt line (cursor was
    // moved to row 2, col 1 -> index 1).
    expect(nonEmptyRows, [1],
        reason: 'live screen rows holding text after cls: $nonEmptyRows; '
            'row1=${terminal.buffer.lines[1].toString()}');
    expect(terminal.buffer.lines[1].toString(), contains('inoki@INOKI-ADESKTOP'));
  });
}
