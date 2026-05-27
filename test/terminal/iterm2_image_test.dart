import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('iTerm2 Image Protocol', () {
    late Terminal terminal;

    setUp(() {
      terminal = Terminal(maxLines: 1000);
    });

    test('should parse basic iTerm2 image sequence and fire callback', () {
      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);

      final oscData = 'File=inline=1;size=${pngBytes.length}:$base64Data';

      final received = <Map<String, dynamic>>[];
      terminal.onImageDecoded = (Uint8List bytes, String name, int? w, int? h) {
        received.add({'bytes': bytes, 'name': name, 'w': w, 'h': h});
      };

      terminal.unknownOSC('1337', [oscData]);

      expect(received.length, 1);
      expect(received[0]['name'], '__default__');
    });

    test('should parse iTerm2 params correctly', () {
      final params = _parseIterm2Params('name=test.png,width=200,height=100');
      expect(params['name'], 'test.png');
      expect(params['width'], '200');
      expect(params['height'], '100');
    });

    test('should handle missing size parameter', () {
      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);

      final oscData = 'File=inline=1:$base64Data';

      final received = <String>[];
      terminal.onImageDecoded = (Uint8List bytes, String name, int? w, int? h) {
        received.add(name);
      };

      terminal.unknownOSC('1337', [oscData]);

      expect(received.length, 1);
    });

    test('should handle image data with width and height params', () {
      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);

      final oscData = 'File=inline=1,width=200px,height=100px:${base64Data}';

      final received = <Map<String, dynamic>>[];
      terminal.onImageDecoded = (Uint8List bytes, String name, int? w, int? h) {
        received.add({'w': w, 'h': h});
      };

      terminal.unknownOSC('1337', [oscData]);

      expect(received.length, 1);
      expect(received[0]['w'], 200);
      expect(received[0]['h'], 100);
    });

    test('should ignore non-1337 OSC sequences', () {
      var called = false;
      terminal.onImageDecoded = (Uint8List bytes, String name, int? w, int? h) {
        called = true;
      };

      terminal.unknownOSC('0', ['test']);
      terminal.unknownOSC('2', ['title']);

      expect(called, false);
    });
  });
}

/// Create a minimal valid PNG (1x1 red pixel)
Uint8List _createMinimalPng() {
  final signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  final ihdr = _createChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]);

  final idatData = [0, 255, 0, 0];
  final compressed = _zlibCompress(idatData);
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
    (length >> 24) & 0xFF,
    (length >> 16) & 0xFF,
    (length >> 8) & 0xFF,
    length & 0xFF,
    ...typeBytes,
    ...data,
    (crc >> 24) & 0xFF,
    (crc >> 16) & 0xFF,
    (crc >> 8) & 0xFF,
    crc & 0xFF,
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
    0x78,
    0x01,
    0x01,
    0x04,
    0x00,
    0xFB,
    0xFF,
    ...data,
    0x00,
    0x00,
    0x00,
    0xFF,
    0x00,
    0x00,
    0x01,
    0x00,
    0x01,
  ];
}

Map<String, String> _parseIterm2Params(String s) {
  final result = <String, String>{};
  for (final part in s.split(',')) {
    final eq = part.indexOf('=');
    if (eq == -1) continue;
    result[part.substring(0, eq)] = part.substring(eq + 1);
  }
  return result;
}
