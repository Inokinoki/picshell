import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Hardening tests: a terminal renders untrusted remote output, so malformed
/// or hostile escape sequences must never throw, hang, or exhaust memory.
void main() {
  group('SGR parameter bounds (remote-triggerable RangeError)', () {
    for (final seq in [
      '\x1b[38m',
      '\x1b[38;5m',
      '\x1b[38;2m',
      '\x1b[38;2;1m',
      '\x1b[38;2;1;2m',
      '\x1b[48m',
      '\x1b[48;5m',
      '\x1b[48;2m',
      '\x1b[48;2;9;9m',
    ]) {
      test('truncated sequence "$seq" does not throw', () {
        final terminal = Terminal(maxLines: 100);
        expect(() => terminal.write('$seq ok\x1b[0m'), returnsNormally);
        expect(terminal.buffer.lines[0].toString(), contains('ok'));
      });
    }

    test('well-formed 256/RGB colors still apply', () {
      final terminal = Terminal(maxLines: 100);
      terminal.write('\x1b[38;5;196mR\x1b[38;2;0;255;0mG\x1b[0m');
      expect(terminal.buffer.lines[0].toString(), contains('RG'));
    });
  });

  group('OSC size cap', () {
    test('oversized single-shot image sequence is dropped, not emitted',
        () async {
      final terminal = Terminal(maxLines: 100);
      var decoded = 0;
      terminal.onImageDecoded =
          (Uint8List bytes, String name, int? w, int? h,
              {inline = true, preserveAspectRatio = true}) {
            decoded++;
          };

      // > the parser's 4M-char OSC body cap.
      final huge = 'A' * (5 * 1024 * 1024);
      terminal.write('\x1b]1337;File=inline=1:$huge\x07');
      terminal.write('after');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(decoded, 0);
      // The parser must keep working after swallowing the oversized sequence.
      expect(terminal.buffer.lines[0].toString(), contains('after'));
    });
  });

  group('multipart transfer limits', () {
    test('announced size over budget rejects the transfer up front', () async {
      final terminal = Terminal(maxLines: 100);
      var decoded = 0;
      terminal.onImageDecoded =
          (Uint8List bytes, String name, int? w, int? h,
              {inline = true, preserveAspectRatio = true}) {
            decoded++;
          };

      terminal.write('\x1b]1337;MultipartFile=inline=1;size=999999999\x07');
      terminal.write('\x1b]1337;FilePart=${base64.encode([1, 2, 3])}\x07');
      terminal.write('\x1b]1337;FileEnd\x07');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(decoded, 0);
    });

    test('runaway accumulation without FileEnd is capped', () async {
      final terminal = Terminal(maxLines: 100);
      var decoded = 0;
      terminal.onImageDecoded =
          (Uint8List bytes, String name, int? w, int? h,
              {inline = true, preserveAspectRatio = true}) {
            decoded++;
          };

      // Exceed the 16 MiB encoded budget (base64 ≈ 4/3 × decoded).
      final chunk = 'A' * (12 * 1024 * 1024);
      terminal.write('\x1b]1337;MultipartFile=inline=1\x07');
      terminal.write('\x1b]1337;FilePart=$chunk\x07');
      terminal.write('\x1b]1337;FilePart=$chunk\x07');
      // A subsequent transfer announcement must discard the runaway buffer.
      terminal.write('\x1b]1337;MultipartFile=inline=1\x07');
      terminal.write('\x1b]1337;FileEnd\x07');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(decoded, 0);
    });

    test('empty FileEnd emits nothing', () async {
      final terminal = Terminal(maxLines: 100);
      var decoded = 0;
      terminal.onImageDecoded =
          (Uint8List bytes, String name, int? w, int? h,
              {inline = true, preserveAspectRatio = true}) {
            decoded++;
          };

      terminal.write('\x1b]1337;MultipartFile=inline=1\x07');
      terminal.write('\x1b]1337;FileEnd\x07');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(decoded, 0);
    });
  });
}
