import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/models/terminal_palette.dart';

void main() {
  group('TerminalPalette', () {
    test('every palette exposes a fully-populated theme', () {
      for (final palette in TerminalPalette.values) {
        final theme = palette.theme;
        // All ANSI colours must be set (opaque, i.e. alpha != 0 would be too
        // strict for selection/cursor, but the 16 ANSI slots + bg/fg must be
        // fully opaque). Color.a is a double in [0, 1].
        expect(theme.background.a, 1.0, reason: '${palette.name} bg');
        expect(theme.foreground.a, 1.0, reason: '${palette.name} fg');
        for (final c in [
          theme.black, theme.red, theme.green, theme.yellow,
          theme.blue, theme.magenta, theme.cyan, theme.white,
          theme.brightBlack, theme.brightRed, theme.brightGreen,
          theme.brightYellow, theme.brightBlue, theme.brightMagenta,
          theme.brightCyan, theme.brightWhite,
        ]) {
          expect(c.a, 1.0, reason: '${palette.name} ANSI colour');
        }
        // Search-hit colours are shared and must be defined.
        expect(theme.searchHitBackground, isNotNull);
        expect(theme.searchHitBackgroundCurrent, isNotNull);
      }
    });

    test('every palette has a non-empty display name', () {
      for (final palette in TerminalPalette.values) {
        expect(palette.displayName.isNotEmpty, true, reason: palette.name);
      }
    });

    test('palette index is stable (order must not change)', () {
      // New schemes are appended; stored Hive indices depend on this order.
      expect(TerminalPalette.values.first, TerminalPalette.defaultTheme);
      expect(
        TerminalPalette.values.indexOf(TerminalPalette.gruvboxDark),
        7,
      );
    });

    test('distinct palettes have distinct backgrounds', () {
      final bgs = <int>{
        for (final p in TerminalPalette.values) p.theme.background.toARGB32()
      };
      // Most palettes use unique backgrounds; at minimum several differ.
      expect(bgs.length, greaterThan(4));
    });

    test('preview colours mirror the theme', () {
      for (final palette in TerminalPalette.values) {
        expect(palette.previewBackground, palette.theme.background);
        expect(palette.previewForeground, palette.theme.foreground);
      }
    });
  });
}
