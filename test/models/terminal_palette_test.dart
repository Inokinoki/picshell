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

    test('named palettes pin canonical background values', () {
      // Guards against copy-paste hex typos (e.g. Gruvbox once shipped
      // 0xFF282822 instead of morhetz's dark0 #282828).
      final pinned = <TerminalPalette, int>{
        TerminalPalette.defaultTheme: 0xFF1E1E1E,
        TerminalPalette.solarizedDark: 0xFF002B36,
        TerminalPalette.solarizedLight: 0xFFFDF6E3,
        TerminalPalette.dracula: 0xFF282A36,
        TerminalPalette.nord: 0xFF2E3440,
        TerminalPalette.monokai: 0xFF272822,
        TerminalPalette.gruvboxDark: 0xFF282828,
      };
      pinned.forEach((palette, value) {
        expect(palette.theme.background.toARGB32(), value,
            reason: palette.name);
      });
    });
  });
}
