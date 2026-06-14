import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('iTerm2 full pipeline integration', () {
    test('terminal.write() with full escape sequence fires callback', () async {
      final terminal = Terminal(maxLines: 1000);

      final received = <Map<String, dynamic>>[];
      terminal.onImageDecoded = (Uint8List bytes, String name, int? w, int? h) {
        received.add({
          'bytes': bytes,
          'name': name,
          'w': w,
          'h': h,
        });
      };

      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);
      final escSeq = '\x1b]1337;File=inline=1;size=${pngBytes.length}:$base64Data\x07';

      terminal.write(escSeq);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(received.length, 1);
      expect(received[0]['bytes'].length, pngBytes.length);
    });

    test('terminal.write() with chunked data fires callback', () async {
      final terminal = Terminal(maxLines: 1000);

      final received = <Uint8List>[];
      terminal.onImageDecoded = (Uint8List bytes, String name, int? w, int? h) {
        received.add(bytes);
      };

      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);
      final escSeq = '\x1b]1337;File=inline=1;size=${pngBytes.length}:$base64Data\x07';

      final midPoint = escSeq.length ~/ 2;
      terminal.write(escSeq.substring(0, midPoint));
      await Future.delayed(const Duration(milliseconds: 50));
      terminal.write(escSeq.substring(midPoint));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received.length, 1);
    });

    test('terminal.write() with multiple chunks fires callback', () async {
      final terminal = Terminal(maxLines: 1000);

      final received = <Uint8List>[];
      terminal.onImageDecoded = (Uint8List bytes, String name, int? w, int? h) {
        received.add(bytes);
      };

      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);
      final escSeq = '\x1b]1337;File=inline=1;size=${pngBytes.length}:$base64Data\x07';

      for (int i = 0; i < escSeq.length; i += 10) {
        final end = (i + 10).clamp(0, escSeq.length);
        terminal.write(escSeq.substring(i, end));
        await Future.delayed(const Duration(milliseconds: 5));
      }

      await Future.delayed(const Duration(milliseconds: 100));

      expect(received.length, 1);
    });

    test('terminal.write() with text before and after image', () async {
      final terminal = Terminal(maxLines: 1000);

      final received = <String>[];
      terminal.onImageDecoded = (Uint8List bytes, String name, int? w, int? h) {
        received.add(name);
      };

      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);
      final escSeq = '\x1b]1337;File=inline=1;size=${pngBytes.length}:$base64Data\x07';

      terminal.write('before image\r\n');
      await Future.delayed(const Duration(milliseconds: 50));
      terminal.write(escSeq);
      await Future.delayed(const Duration(milliseconds: 50));
      terminal.write('after image\r\n');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received.length, 1);
    });

    test('terminal.write() with larger PNG (64x64)', () async {
      final terminal = Terminal(maxLines: 1000);

      final received = <int>[];
      terminal.onImageDecoded = (Uint8List bytes, String name, int? w, int? h) {
        received.add(bytes.length);
      };

      final pngBytes = _createGradientPng(64, 64);
      final base64Data = base64.encode(pngBytes);
      final escSeq = '\x1b]1337;File=inline=1;size=${pngBytes.length}:$base64Data\x07';

      terminal.write(escSeq);
      await Future.delayed(const Duration(milliseconds: 200));

      expect(received.length, 1);
      expect(received[0], pngBytes.length);
    });

    test('BEL terminator works', () async {
      final terminal = Terminal(maxLines: 1000);

      final received = <int>[];
      terminal.onImageDecoded = (Uint8List bytes, String name, int? w, int? h) {
        received.add(bytes.length);
      };

      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);
      final escSeq = '\x1b]1337;File=inline=1;size=${pngBytes.length}:$base64Data\x07';

      terminal.write(escSeq);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received.length, 1);
    });

    test('ST terminator (ESC backslash) works', () async {
      final terminal = Terminal(maxLines: 1000);

      final received = <int>[];
      terminal.onImageDecoded = (Uint8List bytes, String name, int? w, int? h) {
        received.add(bytes.length);
      };

      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);
      final escSeq = '\x1b]1337;File=inline=1;size=${pngBytes.length}:$base64Data\x1b\\';

      terminal.write(escSeq);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received.length, 1);
    });

    test('semicolon in params is handled correctly', () async {
      final terminal = Terminal(maxLines: 1000);

      final received = <Map<String, dynamic>>[];
      terminal.onImageDecoded = (Uint8List bytes, String name, int? w, int? h) {
        received.add({'name': name, 'bytes_len': bytes.length});
      };

      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);
      final escSeq = '\x1b]1337;File=inline=1;name=test.png;size=${pngBytes.length}:$base64Data\x07';

      terminal.write(escSeq);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received.length, 1);
      expect(received[0]['bytes_len'], pngBytes.length);
    });
  });
}

Uint8List _createMinimalPng() {
  final signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  final ihdr = _createChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]);
  final idatData = [0, 255, 0, 0];
  final compressed = _zlibCompress(idatData);
  final idat = _createChunk('IDAT', compressed);
  final iend = _createChunk('IEND', []);
  return Uint8List.fromList([...signature, ...ihdr, ...idat, ...iend]);
}

Uint8List _createGradientPng(int width, int height) {
  final signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  final ihdrData = [
    (width >> 24) & 0xFF, (width >> 16) & 0xFF, (width >> 8) & 0xFF, width & 0xFF,
    (height >> 24) & 0xFF, (height >> 16) & 0xFF, (height >> 8) & 0xFF, height & 0xFF,
    8, 2, 0, 0, 0,
  ];
  final ihdr = _createChunk('IHDR', ihdrData);

  final raw = <int>[];
  for (int y = 0; y < height; y++) {
    raw.add(0);
    for (int x = 0; x < width; x++) {
      raw.add((255 * x ~/ width) & 0xFF);
      raw.add((255 * y ~/ height) & 0xFF);
      raw.add(128);
    }
  }

  final compressed = zlibEncode(raw);
  final idat = _createChunk('IDAT', compressed);
  final iend = _createChunk('IEND', []);

  return Uint8List.fromList([...signature, ...ihdr, ...idat, ...iend]);
}

List<int> _createChunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final length = data.length;
  final crcData = [...typeBytes, ...data];
  final crc = _crc32(crcData);
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
      if (crc & 1 != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc ^ 0xFFFFFFFF;
}

List<int> _zlibCompress(List<int> data) {
  return [
    0x78, 0x01, 0x01, 0x04, 0x00, 0xFB, 0xFF,
    ...data,
    0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x01, 0x00, 0x01,
  ];
}

List<int> zlibEncode(List<int> raw) {
  final data = raw.map((e) => e & 0xFF).toList();
  final compressed = <int>[];

  int pos = 0;
  while (pos < data.length) {
    final len = (data.length - pos).clamp(0, 65535);
    compressed.add(0x78);
    compressed.add(0x01);

    if (pos == 0) {
      compressed.add(0x01);
    } else {
      compressed.add(0x00);
    }
    compressed.add(len & 0xFF);
    compressed.add((len >> 8) & 0xFF);
    compressed.add((~len) & 0xFF);
    compressed.add(((~len) >> 8) & 0xFF);
    compressed.addAll(data.sublist(pos, pos + len));
    pos += len;
  }

  compressed.addAll([0x78, 0x01, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]);
  return compressed;
}
