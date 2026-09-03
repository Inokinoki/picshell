import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// A valid 1×1 PNG (transparent), as emitted by most image tools.
const _png1x1B64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

// ST (String Terminator) = ESC backslash.
const _st = '\x1b\\';

void main() {
  group('Kitty graphics protocol', () {
    late Terminal terminal;
    late List<Map<String, dynamic>> received;

    setUp(() {
      terminal = Terminal(maxLines: 1000);
      received = [];
      terminal.onImageDecoded = (
        Uint8List bytes,
        String name,
        Iterm2Dimension? w,
        Iterm2Dimension? h, {
        inline = true,
        preserveAspectRatio = true,
      }) {
        received.add({
          'bytes': bytes,
          'name': name,
          'w': w?.value,
          'h': h?.value,
        });
      };
    });

    test('single-chunk PNG fires onImageDecoded with the bytes', () {
      final png = base64.decode(_png1x1B64);
      final b64 = base64.encode(png);
      terminal.write('\x1b_Ga=T,f=100,s=1,v=1;$b64$_st');

      expect(received.length, 1);
      expect(received[0]['bytes'], png);
      expect(received[0]['name'], 'kitty');
      expect(received[0]['w'], 1);
      expect(received[0]['h'], 1);
    });

    test('carries the image id into the name when present', () {
      final b64 = _png1x1B64;
      terminal.write('\x1b_Ga=T,f=100,i=42;$b64$_st');
      expect(received.length, 1);
      expect(received[0]['name'], 'kitty-42');
    });

    test('multi-chunk transfer reassembles into one image', () {
      final png = base64.decode(_png1x1B64);
      final b64 = base64.encode(png);
      // Split the base64 into three uneven chunks.
      final mid = b64.length ~/ 3;
      final p1 = b64.substring(0, mid);
      final p2 = b64.substring(mid, mid * 2);
      final p3 = b64.substring(mid * 2);

      terminal.write('\x1b_Ga=T,f=100,m=1;$p1$_st');
      // Nothing emitted yet.
      expect(received.length, 0);

      terminal.write('\x1b_Gm=1;$p2$_st');
      expect(received.length, 0);

      terminal.write('\x1b_Gm=0;$p3$_st');
      expect(received.length, 1);
      expect(received[0]['bytes'], png);
    });

    test('unsupported raw format (f=24) is dropped, not corrupted', () {
      terminal.write('\x1b_Ga=T,f=24,s=1,v=1;AAAA$_st');
      expect(received.length, 0);
    });

    test('malformed base64 is dropped without throwing', () {
      terminal.write('\x1b_Ga=T,f=100;!!!not-base64!!!$_st');
      expect(received.length, 0);
    });

    test('APC for a non-Graphics command is ignored', () {
      // Kitty also uses APC for non-graphics (e.g. 'E' for IPC). Must not
      // crash or emit an image.
      terminal.write('\x1b_Esome-payload$_st');
      expect(received.length, 0);
    });

    test('ST terminator split across write() chunks still decodes', () {
      final png = base64.decode(_png1x1B64);
      final b64 = base64.encode(png);
      final seq = '\x1b_Ga=T,f=100;$b64\x1b\\'; // ends ESC backslash
      // Cut so ESC is the last char of part1 and the backslash starts part2.
      terminal.write(seq.substring(0, seq.length - 1));
      expect(received.length, 0, reason: 'no image before ST completes');
      // And the lone ESC must not leak a backslash into the buffer.
      expect(terminal.buffer.getText(), isNot(contains('\\')));

      terminal.write(seq.substring(seq.length - 1));
      expect(received.length, 1);
      expect(received[0]['bytes'], png);
    });

    test('orphaned multi-chunk transfer does not swallow the next image', () {
      // First image starts chunked (m=1) but its m=0 never arrives.
      terminal.write('\x1b_Ga=T,f=100,i=1,m=1;AAAA$_st');
      expect(received.length, 0);

      // A new image (a=T) arrives — it must emit on its own, not be appended
      // to the orphan's buffer / image id.
      final png = base64.decode(_png1x1B64);
      terminal.write('\x1b_Ga=T,f=100,i=2;${base64.encode(png)}$_st');
      expect(received.length, 1);
      expect(received[0]['name'], 'kitty-2');
      expect(received[0]['bytes'], png);
    });

    test('non-transmit action (a=d) with payload emits nothing', () {
      // A hostile delete/delete-range chunk carrying a payload must not be
      // emitted as a phantom image.
      terminal.write('\x1b_Ga=d,f=100;$_png1x1B64$_st');
      expect(received.length, 0);
      terminal.write('\x1b_Ga=T,f=100;i=9,m=1;AAAA$_st'); // still healthy
      terminal.write(
          '\x1b_Gm=0;${base64.encode(base64.decode(_png1x1B64))}$_st');
      expect(received.length, 1);
    });

    test('oversized APC payload (>4 MiB) is dropped, not accumulated', () {
      // ~5 MiB of base64-ish payload in one APC — over the parser cap.
      final big = 'A' * (5 * 1024 * 1024);
      terminal.write('\x1b_Ga=T,f=100,m=1;$big$_st');
      // The transfer was consumed and dropped; a follow-up image works.
      terminal.write('\x1b_Ga=T,f=100,i=3;${base64.encode(base64.decode(_png1x1B64))}$_st');
      expect(received.length, 1);
      expect(received[0]['name'], 'kitty-3');
    });

    test('unterminated multi-MiB APC stream does not wedge the parser', () {
      // Feed 10 MiB of APC payload *without* a terminator in chunks, then
      // terminate and check the parser recovered: the payload never leaked
      // into the text buffer and following text renders normally.
      const chunkSize = 64 * 1024;
      final chunk = 'B' * chunkSize;
      for (var i = 0; i < (10 * 1024 * 1024) ~/ chunkSize; i++) {
        terminal.write('\x1b_Ga=T,f=100,m=1;$chunk');
      }
      terminal.write(_st);
      terminal.write('done');
      final text = terminal.buffer.getText();
      expect(text, contains('done'));
      expect(text, isNot(contains('BBBB')));
      expect(received.length, 0, reason: 'oversized transfer must be dropped');
    });
    test('oversized OSC payload (>4 MiB) is dropped, not accumulated', () {
      // ~5 MiB of OSC payload in one sequence — over the parser cap. The
      // title must not change and following sequences must be handled.
      final big = 'D' * (5 * 1024 * 1024);
      var title = '';
      terminal.onTitleChange = (t) => title = t;
      terminal.write('\x1b]2;$big\x1b\\');
      expect(title, '');
      terminal.write('\x1b]2;after-osc\x07');
      expect(title, 'after-osc');
    });

    test('unterminated multi-MiB OSC stream does not wedge the parser', () {
      // Feed 10 MiB of OSC payload *without* a terminator in chunks, then
      // terminate and check the parser recovered: the payload never leaked
      // into the text buffer and following text renders normally.
      const chunkSize = 64 * 1024;
      final chunk = 'E' * chunkSize;
      for (var i = 0; i < (10 * 1024 * 1024) ~/ chunkSize; i++) {
        terminal.write('\x1b]0;$chunk');
      }
      terminal.write(_st);
      terminal.write('done');
      final text = terminal.buffer.getText();
      expect(text, contains('done'));
      expect(text, isNot(contains('EEEE')));
    });

    test('semicolon flood in OSC is capped, not accumulated', () {
      // Semicolons used to bypass the cap (each grows _osc by one entry
      // without counting toward _oscLength) — a multi-MiB flood of them must
      // overflow and drop the sequence like payload chars do.
      final flood = ';' * (5 * 1024 * 1024);
      var title = '';
      terminal.onTitleChange = (t) => title = t;
      terminal.write('\x1b]0;victim$flood\x1b\\');
      expect(title, '', reason: 'oversized OSC must be dropped');
      terminal.write('\x1b]2;after-flood\x07');
      expect(title, 'after-flood');
    });

    test('lone-ESC-at-end writes on an overflowed OSC do not wedge the parser',
        () {
      // Every write ends with a lone ESC (split-ST rollback candidate). Once
      // the sequence overflowed it must be consumed (dropped), not rolled
      // back and re-scanned on every write — otherwise the queue grows
      // without bound.
      const chunkSize = 64 * 1024;
      final chunk = 'F' * chunkSize;
      for (var i = 0; i < (10 * 1024 * 1024) ~/ chunkSize; i++) {
        terminal.write('\x1b]0;$chunk\x1b');
      }
      // Terminate the (doomed) sequence and check the parser recovered.
      terminal.write('\\');
      terminal.write('done');
      final text = terminal.buffer.getText();
      expect(text, contains('done'));
      expect(text, isNot(contains('FFFF')));
    });
  });

  group('DCS / Sixel handling', () {
    test('Sixel payload is consumed and does not leak into the buffer', () {
      final terminal = Terminal(maxLines: 1000);
      // A nonsensical but recognizable Sixel-ish DCS: ESC P q "1;1;10;10 #0 ... ST
      terminal.write('\x1bPq"1;1;10;10#0!10~ZZZZ\x1b\\');
      final text = terminal.buffer.getText();
      expect(text, isNot(contains('ZZZZ')));
      expect(text, isNot(contains('!10')));
    });

    test('oversized Sixel DCS payload is dropped, not accumulated', () {
      final terminal = Terminal(maxLines: 1000);
      final big = 'C' * (5 * 1024 * 1024);
      terminal.write('\x1bPq$big\x1b\\');
      terminal.write('ok');
      final text = terminal.buffer.getText();
      expect(text, contains('ok'));
      expect(text, isNot(contains('CCCC')));
    });
  });
}
