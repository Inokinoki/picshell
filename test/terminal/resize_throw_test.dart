import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('resize 80x24 -> 120x30 -> 177x36 does not throw and updates view',
      () {
    final terminal = Terminal(maxLines: 10000);
    // fill some content first (reflow stress)
    for (var i = 0; i < 50; i++) {
      terminal.write(
          'line $i with some content that is reasonably long for wrapping\r\n');
    }
    terminal.resize(120, 30);
    expect(terminal.viewWidth, 120);
    expect(terminal.viewHeight, 30);
    terminal.resize(177, 36);
    expect(terminal.viewWidth, 177, reason: 'viewWidth must update');
    expect(terminal.viewHeight, 36, reason: 'viewHeight must update');
  });

  test('resize with lots of scrollback 80x24 -> 177x36', () {
    final terminal = Terminal(maxLines: 10000);
    for (var i = 0; i < 500; i++) {
      terminal.write(
          'row $i ${'x' * (i % 100)}\r\n');
    }
    terminal.resize(80, 24);
    terminal.resize(177, 36);
    expect(terminal.viewWidth, 177);
    expect(terminal.viewHeight, 36);
  });
}
