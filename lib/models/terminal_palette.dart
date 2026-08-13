import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

/// A selectable terminal colour scheme. Persisted by its [index] in the
/// settings Hive box (see [AppSettings]); the [theme] getter maps each value
/// to a fully-populated [TerminalTheme]. New schemes must be appended here —
/// never reordered — so stored indices stay stable across versions.
enum TerminalPalette {
  defaultTheme,
  whiteOnBlack,
  solarizedDark,
  solarizedLight,
  dracula,
  nord,
  monokai,
  gruvboxDark;

  /// Human-readable name for the settings UI.
  String get displayName {
    switch (this) {
      case TerminalPalette.defaultTheme:
        return 'Picshell (默认)';
      case TerminalPalette.whiteOnBlack:
        return '白字黑底';
      case TerminalPalette.solarizedDark:
        return 'Solarized Dark';
      case TerminalPalette.solarizedLight:
        return 'Solarized Light';
      case TerminalPalette.dracula:
        return 'Dracula';
      case TerminalPalette.nord:
        return 'Nord';
      case TerminalPalette.monokai:
        return 'Monokai';
      case TerminalPalette.gruvboxDark:
        return 'Gruvbox Dark';
    }
  }

  /// The [TerminalTheme] applied to the terminal renderer.
  TerminalTheme get theme {
    switch (this) {
      case TerminalPalette.defaultTheme:
        return TerminalThemes.defaultTheme;
      case TerminalPalette.whiteOnBlack:
        return TerminalThemes.whiteOnBlack;
      case TerminalPalette.solarizedDark:
        return _solarizedDark;
      case TerminalPalette.solarizedLight:
        return _solarizedLight;
      case TerminalPalette.dracula:
        return _dracula;
      case TerminalPalette.nord:
        return _nord;
      case TerminalPalette.monokai:
        return _monokai;
      case TerminalPalette.gruvboxDark:
        return _gruvboxDark;
    }
  }

  /// A small foreground/background pair used for the colour-swatch preview in
  /// the settings UI (avoids materialising the full palette in the tile).
  Color get previewBackground => theme.background;
  Color get previewForeground => theme.foreground;
}

/// Search-highlight colours shared by every scheme. Kept consistent so the
/// scrollback search (Plan 3) reads identically regardless of theme.
const _searchHitBackground = Color(0x80FFEB3B);
const _searchHitBackgroundCurrent = Color(0x804CAF50);
const _searchHitForeground = Color(0xFF000000);

final TerminalTheme _solarizedDark = TerminalTheme(
  cursor: Color(0xFF839496),
  selection: Color(0x662AA198),
  foreground: Color(0xFF839496),
  background: Color(0xFF002B36),
  black: Color(0xFF073642),
  red: Color(0xFFDC322F),
  green: Color(0xFF859900),
  yellow: Color(0xFFB58900),
  blue: Color(0xFF268BD2),
  magenta: Color(0xFFD33682),
  cyan: Color(0xFF2AA198),
  white: Color(0xFFEEE8D5),
  brightBlack: Color(0xFF002B36),
  brightRed: Color(0xFFCB4B16),
  brightGreen: Color(0xFF586E75),
  brightYellow: Color(0xFF657B83),
  brightBlue: Color(0xFF839496),
  brightMagenta: Color(0xFF6C71C4),
  brightCyan: Color(0xFF93A1A1),
  brightWhite: Color(0xFFFDF6E3),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);

final TerminalTheme _solarizedLight = TerminalTheme(
  cursor: Color(0xFF657B83),
  selection: Color(0x662AA198),
  foreground: Color(0xFF657B83),
  background: Color(0xFFFDF6E3),
  black: Color(0xFF073642),
  red: Color(0xFFDC322F),
  green: Color(0xFF859900),
  yellow: Color(0xFFB58900),
  blue: Color(0xFF268BD2),
  magenta: Color(0xFFD33682),
  cyan: Color(0xFF2AA198),
  white: Color(0xFFEEE8D5),
  brightBlack: Color(0xFF002B36),
  brightRed: Color(0xFFCB4B16),
  brightGreen: Color(0xFF586E75),
  brightYellow: Color(0xFF657B83),
  brightBlue: Color(0xFF839496),
  brightMagenta: Color(0xFF6C71C4),
  brightCyan: Color(0xFF93A1A1),
  brightWhite: Color(0xFFFDF6E3),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);

final TerminalTheme _dracula = TerminalTheme(
  cursor: Color(0xFFF8F8F2),
  selection: Color(0x6644475A),
  foreground: Color(0xFFF8F8F2),
  background: Color(0xFF282A36),
  black: Color(0xFF21222C),
  red: Color(0xFFFF5555),
  green: Color(0xFF50FA7B),
  yellow: Color(0xFFF1FA8C),
  blue: Color(0xFFBD93F9),
  magenta: Color(0xFFFF79C6),
  cyan: Color(0xFF8BE9FD),
  white: Color(0xFFF8F8F2),
  brightBlack: Color(0xFF6272A4),
  brightRed: Color(0xFFFF6E67),
  brightGreen: Color(0xFF5AF78E),
  brightYellow: Color(0xFFF4F99D),
  brightBlue: Color(0xFFCAA9FA),
  brightMagenta: Color(0xFFFF92D0),
  brightCyan: Color(0xFF9AEDFE),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);

final TerminalTheme _nord = TerminalTheme(
  cursor: Color(0xFFD8DEE9),
  selection: Color(0x66434C5E),
  foreground: Color(0xFFD8DEE9),
  background: Color(0xFF2E3440),
  black: Color(0xFF3B4252),
  red: Color(0xFFBF616A),
  green: Color(0xFFA3BE8C),
  yellow: Color(0xFFEBCB8B),
  blue: Color(0xFF81A1C1),
  magenta: Color(0xFFB48EAD),
  cyan: Color(0xFF88C0D0),
  white: Color(0xFFE5E9F0),
  brightBlack: Color(0xFF4C566A),
  brightRed: Color(0xFFBF616A),
  brightGreen: Color(0xFFA3BE8C),
  brightYellow: Color(0xFFEBCB8B),
  brightBlue: Color(0xFF81A1C1),
  brightMagenta: Color(0xFFB48EAD),
  brightCyan: Color(0xFF8FBCBB),
  brightWhite: Color(0xFFECEFF4),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);

final TerminalTheme _monokai = TerminalTheme(
  cursor: Color(0xFFF8F8F0),
  selection: Color(0x6649483E),
  foreground: Color(0xFFF8F8F2),
  background: Color(0xFF272822),
  black: Color(0xFF272822),
  red: Color(0xFFF92672),
  green: Color(0xFFA6E22E),
  yellow: Color(0xFFF4BF75),
  blue: Color(0xFF66D9EF),
  magenta: Color(0xFFAE81FF),
  cyan: Color(0xFFA1EFE4),
  white: Color(0xFFF8F8F2),
  brightBlack: Color(0xFF75715E),
  brightRed: Color(0xFFF92672),
  brightGreen: Color(0xFFA6E22E),
  brightYellow: Color(0xFFF4BF75),
  brightBlue: Color(0xFF66D9EF),
  brightMagenta: Color(0xFFAE81FF),
  brightCyan: Color(0xFFA1EFE4),
  brightWhite: Color(0xFFF9F8F5),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);

final TerminalTheme _gruvboxDark = TerminalTheme(
  cursor: Color(0xFFEBDBB2),
  selection: Color(0x66504945),
  foreground: Color(0xFFEBDBB2),
  background: Color(0xFF282822),
  black: Color(0xFF282822),
  red: Color(0xFFCC241D),
  green: Color(0xFF98971A),
  yellow: Color(0xFFD79921),
  blue: Color(0xFF458588),
  magenta: Color(0xFFB16286),
  cyan: Color(0xFF689D6A),
  white: Color(0xFFA89984),
  brightBlack: Color(0xFF928374),
  brightRed: Color(0xFFFB4934),
  brightGreen: Color(0xFFB8BB26),
  brightYellow: Color(0xFFFABD2F),
  brightBlue: Color(0xFF83A598),
  brightMagenta: Color(0xFFD3869B),
  brightCyan: Color(0xFF8EC07C),
  brightWhite: Color(0xFFEBDBB2),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);
