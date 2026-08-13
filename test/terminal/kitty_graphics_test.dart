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
        int? w,
        int? h, {
        inline = true,
        preserveAspectRatio = true,
      }) {
        received.add({
          'bytes': bytes,
          'name': name,
          'w': w,
          'h': h,
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
  });
}
