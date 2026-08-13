import 'package:xterm/xterm.dart';

/// One match of a [TerminalSearch.find] query: the absolute line index within
/// the terminal buffer (0 = oldest scrollback line) and the character column
/// span within that line.
class SearchMatch {
  final int lineIndex;
  final int colStart;
  final int colEnd;

  const SearchMatch({
    required this.lineIndex,
    required this.colStart,
    required this.colEnd,
  });

  int get length => colEnd - colStart;
}

/// Plain-text search over a terminal's full buffer (scrollback + viewport).
///
/// The xterm package exposes no search API, so this iterates [Terminal.buffer]
/// line by line. Each match is returned as an absolute [lineIndex] + column
/// range, which the UI turns into stable [CellAnchor]s for highlighting and a
/// scroll offset for navigation. Results are capped ([maxMatches]) to bound
/// work on very large scrollbacks.
class TerminalSearch {
  TerminalSearch(this.terminal);

  final Terminal terminal;

  /// Maximum matches collected per query, to keep highlighting responsive on
  /// huge buffers. The counter surfaces how many were truncated.
  static const maxMatches = 500;

  /// Searches the buffer for [query].
  ///
  /// When [regex] is true, [query] is compiled as a [RegExp] (honouring
  /// [caseSensitive]); otherwise it is a literal substring match. Returns the
  /// matches plus [truncated] (true if [maxMatches] was hit).
  SearchResult find(
    String query, {
    bool caseSensitive = false,
    bool regex = false,
  }) {
    if (query.isEmpty) return const SearchResult(matches: [], truncated: false);

    final buffer = terminal.buffer;
    final matches = <SearchMatch>[];
    var truncated = false;

    final RegExp? pattern =
        regex ? RegExp(query, caseSensitive: caseSensitive) : null;
    final String needle;
    if (!regex) {
      needle = caseSensitive ? query : query.toLowerCase();
    } else {
      needle = ''; // unused
    }

    for (var y = 0; y < buffer.height; y++) {
      final text = buffer.lines[y].getText();
      if (regex) {
        for (final m in pattern!.allMatches(text)) {
          if (matches.length >= maxMatches) {
            truncated = true;
            break;
          }
          matches.add(SearchMatch(
              lineIndex: y, colStart: m.start, colEnd: m.end));
        }
        if (truncated) break;
      } else {
        final hay = caseSensitive ? text : text.toLowerCase();
        var from = 0;
        while (true) {
          final idx = hay.indexOf(needle, from);
          if (idx == -1) break;
          if (matches.length >= maxMatches) {
            truncated = true;
            break;
          }
          matches.add(SearchMatch(
              lineIndex: y, colStart: idx, colEnd: idx + needle.length));
          from = idx + 1;
        }
        if (truncated) break;
      }
    }
    return SearchResult(matches: matches, truncated: truncated);
  }
}

class SearchResult {
  final List<SearchMatch> matches;
  final bool truncated;

  const SearchResult({required this.matches, required this.truncated});
}
