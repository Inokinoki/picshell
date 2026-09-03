import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Tests for the extended iTerm2 image protocol handling: multipart
/// (MultipartFile/FilePart/FileEnd), the inline / preserveAspectRatio flags,
/// and percent-encoded width dimensions. Lives separately from the original
/// pipeline tests so each concern is isolated.
void main() {
  Uint8List minimalPng() {
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    final ihdr = _chunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]);
    final idat = _chunk('IDAT', [0x78, 0x01, 0x01, 0x04, 0x00, 0xFB, 0xFF, 0, 255, 0, 0,
      0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x01, 0x00, 0x01]);
    final iend = _chunk('IEND', []);
    return Uint8List.fromList([...signature, ...ihdr, ...idat, ...iend]);
  }

  group('iTerm2 protocol flags', () {
    test('inline=1 sets inline true', () async {
      final terminal = Terminal(maxLines: 1000);
      bool? capturedInline;
      terminal.onImageDecoded = (bytes, name, w, h, {inline = true, preserveAspectRatio = true}) {
        capturedInline = inline;
      };

      final png = minimalPng();
      final b64 = base64.encode(png);
      terminal.write('\x1b]1337;File=inline=1;size=${png.length}:$b64\x07');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(capturedInline, true);
    });

    test('inline=0 (default) sets inline false', () async {
      final terminal = Terminal(maxLines: 1000);
      bool? capturedInline;
      terminal.onImageDecoded = (bytes, name, w, h, {inline = true, preserveAspectRatio = true}) {
        capturedInline = inline;
      };

      final png = minimalPng();
      final b64 = base64.encode(png);
      // No inline= → defaults to 0 (download), i.e. inline=false.
      terminal.write('\x1b]1337;File=name=x;size=${png.length}:$b64\x07');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(capturedInline, false);
    });

    test('preserveAspectRatio=0 sets flag false', () async {
      final terminal = Terminal(maxLines: 1000);
      bool? par;
      terminal.onImageDecoded = (bytes, name, w, h, {inline = true, preserveAspectRatio = true}) {
        par = preserveAspectRatio;
      };

      final png = minimalPng();
      final b64 = base64.encode(png);
      terminal.write('\x1b]1337;File=inline=1;preserveAspectRatio=0;size=${png.length}:$b64\x07');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(par, false);
    });

    test('preserveAspectRatio defaults to true', () async {
      final terminal = Terminal(maxLines: 1000);
      bool? par;
      terminal.onImageDecoded = (bytes, name, w, h, {inline = true, preserveAspectRatio = true}) {
        par = preserveAspectRatio;
      };

      final png = minimalPng();
      final b64 = base64.encode(png);
      terminal.write('\x1b]1337;File=inline=1;size=${png.length}:$b64\x07');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(par, true);
    });

    test('bare N means cells, N% means percent, Npx means pixels', () async {
      final terminal = Terminal(maxLines: 1000);
      final dims = <(Iterm2Dimension?, Iterm2Dimension?)>[];
      terminal.onImageDecoded = (bytes, name, width, height, {inline = true, preserveAspectRatio = true}) {
        dims.add((width, height));
      };

      final png = minimalPng();
      final b64 = base64.encode(png);
      terminal.write('\x1b]1337;File=inline=1;width=50%;height=12px;size=${png.length}:$b64\x07');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(dims, hasLength(1));
      final (w, h) = dims.single;
      // Per the iTerm2 spec, units are preserved for the widget layer.
      expect(w?.value, 50);
      expect(w?.unit, Iterm2Unit.percent);
      expect(h?.value, 12);
      expect(h?.unit, Iterm2Unit.pixels);
    });

    test('name is base64-decoded', () async {
      final terminal = Terminal(maxLines: 1000);
      String? decodedName;
      terminal.onImageDecoded = (bytes, name, w, h, {inline = true, preserveAspectRatio = true}) {
        decodedName = name;
      };

      final png = minimalPng();
      final b64 = base64.encode(png);
      // "chart.png" base64-encoded.
      final nameB64 = base64.encode(utf8.encode('chart.png'));
      terminal.write('\x1b]1337;File=inline=1;name=$nameB64;size=${png.length}:$b64\x07');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(decodedName, 'chart.png');
    });
  });

  group('iTerm2 multipart transfer (MultipartFile/FilePart/FileEnd)', () {
    test('single FilePart assembles and fires once', () async {
      final terminal = Terminal(maxLines: 1000);
      final received = <int>[];
      terminal.onImageDecoded = (bytes, name, w, h, {inline = true, preserveAspectRatio = true}) {
        received.add(bytes.length);
      };

      final png = minimalPng();
      final b64 = base64.encode(png);

      terminal.write('\x1b]1337;MultipartFile=inline=1;size=${png.length}\x07');
      terminal.write('\x1b]1337;FilePart=$b64\x07');
      terminal.write('\x1b]1337;FileEnd\x07');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received.length, 1);
      expect(received[0], png.length);
    });

    test('multiple FileParts concatenate in order', () async {
      final terminal = Terminal(maxLines: 1000);
      Uint8List? got;
      terminal.onImageDecoded = (bytes, name, w, h, {inline = true, preserveAspectRatio = true}) {
        got = bytes;
      };

      final png = minimalPng();
      final b64 = base64.encode(png);
      final mid = b64.length ~/ 2;

      terminal.write('\x1b]1337;MultipartFile=inline=1\x07');
      terminal.write('\x1b]1337;FilePart=${b64.substring(0, mid)}\x07');
      terminal.write('\x1b]1337;FilePart=${b64.substring(mid)}\x07');
      terminal.write('\x1b]1337;FileEnd\x07');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(got, isNotNull);
      expect(got!.length, png.length);
    });

    test('FilePart without MultipartFile is ignored', () async {
      final terminal = Terminal(maxLines: 1000);
      var called = false;
      terminal.onImageDecoded = (bytes, name, w, h, {inline = true, preserveAspectRatio = true}) {
        called = true;
      };

      terminal.write('\x1b]1337;FilePart=${base64.encode(minimalPng())}\x07');
      terminal.write('\x1b]1337;FileEnd\x07');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(called, false);
    });
  });
}

List<int> _chunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final crcData = [...typeBytes, ...data];
  final crc = _crc32(crcData);
  final length = data.length;
  return [
    (length >> 24) & 0xFF, (length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF,
    ...typeBytes, ...data,
    (crc >> 24) & 0xFF, (crc >> 16) & 0xFF, (crc >> 8) & 0xFF, crc & 0xFF,
  ];
}

int _crc32(List<int> data) {
  int crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (int i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
