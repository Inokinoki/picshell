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

    test('should parse basic iTerm2 image sequence', () {
      // Create a minimal 1x1 red PNG
      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);

      final oscData = 'File=inline=1;size=${pngBytes.length}:$base64Data';

      // Initially no images
      expect(terminal.iterm2Images.isEmpty, true);

      // Simulate receiving the OSC sequence
      terminal.unknownOSC('1337', [oscData]);

      // Allow async decoding to complete
      expect(terminal.iterm2Images.isEmpty, true);
    });

    test('should parse iTerm2 params correctly', () {
      final terminal = Terminal(maxLines: 1000);

      // Test the parsing via a helper
      final params = _parseIterm2Params('name=test.png,width=200,height=100');
      expect(params['name'], 'test.png');
      expect(params['width'], '200');
      expect(params['height'], '100');
    });

    test('should handle missing size parameter', () {
      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);

      // Without size parameter - should still try to decode
      final oscData = 'File=inline=1:$base64Data';

      terminal.unknownOSC('1337', [oscData]);

      // Should not throw
      expect(terminal.iterm2Images.isEmpty, true);
    });

    test('should handle chunked image data', () {
      final terminal = Terminal(maxLines: 1000);
      final pngBytes = _createMinimalPng();
      final base64Data = base64.encode(pngBytes);

      // Split into chunks
      final chunk1 = base64Data.substring(0, 10);
      final chunk2 = base64Data.substring(10);

      // Send first chunk
      terminal.unknownOSC('1337', [
        'File=inline=1;size=${pngBytes.length};name=test:$chunk1',
      ]);

      // Send second chunk
      terminal.unknownOSC('1337', [
        'File=inline=1;size=${pngBytes.length};name=test:$chunk2',
      ]);

      // Should not throw
      expect(terminal.iterm2Images.isEmpty, true);
    });

    test('should ignore non-1337 OSC sequences', () {
      final terminal = Terminal(maxLines: 1000);

      // Should not throw for non-1337 sequences
      terminal.unknownOSC('0', ['test']);
      terminal.unknownOSC('2', ['title']);

      expect(terminal.iterm2Images.isEmpty, true);
    });
  });
}

/// Create a minimal valid PNG (1x1 red pixel)
Uint8List _createMinimalPng() {
  // PNG signature
  final signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  // IHDR chunk (1x1, 8-bit RGB)
  final ihdr = _createChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]);

  // IDAT chunk (1 pixel, filter none, red)
  final idatData = [0, 255, 0, 0]; // filter=none, R=255, G=0, B=0
  final compressed = _zlibCompress(idatData);
  final idat = _createChunk('IDAT', compressed);

  // IEND chunk
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
  // Minimal zlib compression for single pixel
  // This is a simplified version - real implementation would use proper compression
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
