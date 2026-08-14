import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/graphics/png_encoder.dart';
import 'package:xterm/xterm.dart';

/// Real-world fixture coverage:
///  - a sixel sequence produced by `img2sixel` (libsixel 1.8.7) from a
///    PIL-generated 16×8 RGB gradient PNG, and
///  - the source PNG itself.
///
/// The fixtures live in test/fixtures/ (regenerate with:
/// `python3 -c '...gradient...' && img2sixel gradient16x8.png > ...`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('real img2sixel fixture', () {
    final available =
        File('test/fixtures/gradient16x8.sixel').existsSync() &&
            File('test/fixtures/gradient16x8.png').existsSync();

    test('decodes to the same pixels as the source PNG', () async {
      // Guard: fixtures are committed, but skip meaningfully if absent.
      if (!available) {
        // ignore: avoid_print
        print('fixtures missing — skipping');
        return;
      }

      // Feed the raw DCS sequence (it already includes ESC P ... ESC \).
      final sixel =
          File('test/fixtures/gradient16x8.sixel').readAsStringSync(encoding: latin1);
      final terminal = Terminal(maxLines: 100);
      final received = <Map<String, dynamic>>[];
      terminal.onImageDecoded = (
        Uint8List bytes,
        String name,
        int? w,
        int? h, {
        inline = true,
        preserveAspectRatio = true,
      }) {
        received.add({'bytes': bytes, 'name': name, 'w': w, 'h': h});
      };
      terminal.write(sixel);

      expect(received.length, 1, reason: 'fixture must decode to one image');
      expect(received[0]['name'], 'sixel');
      expect(received[0]['w'], 16, reason: 'fixture is 16 px wide');

      // Decode BOTH the fixture output and the source PNG via the platform
      // decoder, then compare pixels over the drawn 16×8 area.
      final sixelRgba = await _decodePng(received[0]['bytes'] as Uint8List);
      final srcRgba = await _decodePng(
          File('test/fixtures/gradient16x8.png').readAsBytesSync());
      expect(sixelRgba.$1, 16);
      expect(sixelRgba.$2 >= 8, isTrue, reason: 'at least the drawn 8 rows');

      var beyondTolerance = 0;
      for (var i = 0; i < 16 * 8; i++) {
        for (var c = 0; c < 4; c++) {
          final diff =
              ((sixelRgba.$3)[i * 4 + c] - srcRgba.$3[i * 4 + c]).abs();
          if (diff > 6) beyondTolerance++;
        }
      }
      // libsixel quantises colours to 0-100 RGB registers, so a ±2-3 rounding
      // error per channel is expected; anything beyond the tolerance would
      // indicate a decode/alignment problem.
      expect(beyondTolerance, 0,
          reason: 'every channel must survive the sixel round-trip ±6');
    }, skip: available ? false : 'fixtures not present');

    test('produced PNG decodes and round-trips pixels (pngEncode)', () async {
      // 3×2 RGBA with distinct known pixels.
      final w = 3, h = 2;
      // NOTE: pixels are fully opaque or fully transparent black — the
      // platform decoder stores images premultiplied internally, so a
      // semi/zero-alpha pixel with non-zero RGB would not round-trip exactly
      // (un-premultiply zeroes it). That is decoder behaviour, not an encoder
      // property, so exact comparison uses these.
      final rgba = Uint8List.fromList([
        255, 0, 0, 255, //
        0, 255, 0, 255, //
        0, 0, 255, 255, //
        255, 255, 0, 255, //
        0, 255, 255, 255, //
        0, 0, 0, 0,
      ]);
      final png = pngEncode(rgba, w, h);

      // Decode with the PLATFORM decoder (independent of our encoder) and
      // verify every pixel — proves CRC, IDAT and IHDR are all well-formed.
      final decoded = await _decodePng(png);
      expect(decoded.$1, w);
      expect(decoded.$2, h);
      for (var i = 0; i < rgba.length; i++) {
        expect(decoded.$3[i], rgba[i], reason: 'byte $i');
      }
    });
  });
}

/// Decodes [png] via dart:ui; returns (width, height, rgba).
Future<(int, int, Uint8List)> _decodePng(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data =
      await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final bytes = data!.buffer.asUint8List();
  final out = (image.width, image.height, bytes);
  image.dispose();
  codec.dispose();
  return out;
}
