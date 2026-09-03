import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/graphics/png_encoder.dart';
import 'package:xterm/src/graphics/sixel.dart';
import 'package:xterm/xterm.dart';

const _st = '\x1b\\';

void main() {
  group('SixelDecoder', () {
    test('a single colour-register block rasterises to a filled rectangle',
        () {
      // #0;2;100;0;0  -> register 0 = RGB red
      // !4~            -> 4 columns of ~ (all 6 bits) → 4×6 block
      final img = SixelDecoder().decode('#0;2;100;0;0!4~')!;

      expect(img.width, 4);
      expect(img.height, 6);

      int pixel(int x, int y) {
        final i = (y * img.width + x) * 4;
        return img.rgba[i] << 24 | img.rgba[i + 1] << 16 |
            img.rgba[i + 2] << 8 | img.rgba[i + 3];
      }

      // Every pixel red, opaque.
      for (var y = 0; y < 6; y++) {
        for (var x = 0; x < 4; x++) {
          expect(pixel(x, y), 0xFF0000FF, reason: '($x,$y)'); // RGBA big-endian
        }
      }
    });

    test('`-` advances one 6-row band', () {
      final img = SixelDecoder().decode('#0;2;0;100;0!2~-!2~')!;
      expect(img.width, 2);
      expect(img.height, 12); // two bands of 6

      // Pixel in band 0 (y=0) and band 1 (y=6) both green & opaque.
      int px(int x, int y) {
        final i = (y * img.width + x) * 4;
        return img.rgba[i + 3]; // alpha
      }
      expect(px(0, 0), 255);
      expect(px(0, 6), 255);
    });

    test('RGB components scale 0-100 → 0-255', () {
      // 100% → 255, 0% → 0 (FP-clean endpoints).
      final img = SixelDecoder().decode('#0;2;100;50;0~')!;
      expect(img.rgba[0], 255); // R @ 100%
      // 50% → ~127 (50 * 2.55 has FP representation drift)
      expect(img.rgba[1], closeTo(127, 1));
      expect(img.rgba[2], 0); // B @ 0%
    });

    test('unset bits within a sixel column stay transparent', () {
      // `@` = 0x40, bits = 0x01 → only the top pixel of the column is set.
      final img = SixelDecoder().decode('#0;2;100;0;0@')!;
      expect(img.width, 1);
      expect(img.height, 6);
      // (0,0) red, opaque.
      expect(img.rgba[0], 255); // R
      expect(img.rgba[3], 255); // A
      // (0,1) transparent.
      final i1 = (1 * img.width + 0) * 4;
      expect(img.rgba[i1 + 3], 0);
    });

    test('empty / whitespace data returns null', () {
      expect(SixelDecoder().decode(''), isNull);
      expect(SixelDecoder().decode('   '), isNull);
    });

    test('register numbers above 65535 are skipped, not stored', () {
      // A register definition far beyond the DEC 2^16-1 limit followed by a
      // selection of it: the definition is skipped (falls back to white), and
      // the palette map doesn't grow per hostile definition.
      final img = SixelDecoder().decode(
        '#99999999;2;0;100;0#99999999!2~',
      )!;
      expect(img.width, 2);
      // White fallback: R=G=B=255, opaque.
      expect(img.rgba[0], 255);
      expect(img.rgba[1], 255);
      expect(img.rgba[2], 255);
      expect(img.rgba[3], 255);
    });

    test('register 65535 is still honoured', () {
      final img = SixelDecoder().decode('#65535;2;100;0;0#65535!2~')!;
      expect(img.rgba[0], 255); // red, not the white fallback
      expect(img.rgba[1], 0);
      expect(img.rgba[3], 255);
    });

    test('many distinct hostile register numbers decode without error', () {
      final b = StringBuffer();
      for (var n = 0; n < 200000; n++) {
        b.write('#${100000 + n};2;0;0;0');
      }
      b.write('!2~');
      final img = SixelDecoder().decode(b.toString())!;
      expect(img.width, 2);
    });
  });

  group('pngEncode', () {
    test('produces a PNG with the correct signature and dimensions', () {
      // 2×2 RGBA, all opaque red.
      final rgba = Uint8List.fromList([
        255, 0, 0, 255, 255, 0, 0, 255,
        255, 0, 0, 255, 255, 0, 0, 255,
      ]);
      final png = pngEncode(rgba, 2, 2);

      // PNG signature (8), then IHDR: length(4)=13 at [8,12], type 'IHDR' at
      // [12,16], width(4 BE) at [16,20], height(4 BE) at [20,24].
      expect(png.sublist(0, 8),
          [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
      expect(String.fromCharCodes(png.sublist(12, 16)), 'IHDR');
      final w = png.sublist(16, 20).fold<int>(0, (a, b) => a << 8 | b);
      final h = png.sublist(20, 24).fold<int>(0, (a, b) => a << 8 | b);
      expect(w, 2);
      expect(h, 2);
    });
  });

  group('Sixel pipeline (DCS)', () {
    test('a Sixel sequence reaches onImageDecoded as PNG bytes', () {
      final terminal = Terminal(maxLines: 1000);
      final received = <Map<String, dynamic>>[];
      terminal.onImageDecoded = (
        Uint8List bytes,
        String name,
        Iterm2Dimension? w,
        Iterm2Dimension? h, {
        inline = true,
        preserveAspectRatio = true,
      }) {
        received.add({'bytes': bytes, 'name': name, 'w': w?.value, 'h': h?.value});
      };

      terminal.write('\x1bP0;0;0q#0;2;100;0;0!4~$_st');

      expect(received.length, 1);
      expect(received[0]['name'], 'sixel');
      expect(received[0]['w'], 4);
      expect(received[0]['h'], 6);
      final bytes = received[0]['bytes'] as Uint8List;
      // Valid PNG signature.
      expect(bytes.sublist(0, 8),
          [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    });

    test('DECRQSS (DCS \$q prefix) is not rasterised into a phantom image', () {
      final terminal = Terminal(maxLines: 1000);
      final received = <String>[];
      terminal.onImageDecoded = (b, n, w, h,
          {inline = true, preserveAspectRatio = true}) => received.add(n);
      // DCS $ q ... ST is a settings query; its text body must not be drawn.
      terminal.write('\x1bP\$qm\x1b\\');
      terminal.write('\x1bP\$q"p\x1b\\');
      expect(received.length, 0);
    });

    test('malformed Sixel never throws out of terminal.write()', () {
      final terminal = Terminal(maxLines: 1000);
      terminal.onImageDecoded = (_, __, ___, ____, {inline = true, preserveAspectRatio = true}) {};
      expect(
        () => terminal.write('\x1bPq#!!!@@@garbage\x1b\\'),
        returnsNormally,
      );
    });
  });

  group('SixelDecoder hardening', () {
    test('a runaway !N repeat is clamped, not spun / OOMed', () {
      final img = SixelDecoder().decode('#0;2;100;0;0!999999999~');
      // Clamped to maxRepeat columns of a single 6-row band.
      expect(img, isNotNull);
      expect(img!.width, SixelDecoder.maxRepeat);
      expect(img.height, 6);
    });
  });
}
