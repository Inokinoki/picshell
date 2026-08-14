import 'package:xterm/xterm.dart';

/// One match of a [TerminalSearch.find] query: the absolute line index within
/// the terminal buffer (0 = oldest scrollback line) and the **cell** column
/// span within that line (cell columns, not character offsets — see
/// [TerminalSearch.find]).
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
/// line by line. Each match is returned as an absolute [lineIndex] + **cell**
/// column range, which the UI turns into stable [CellAnchor]s for highlighting
/// and a scroll offset for navigation. Results are capped ([maxMatches]) to
/// bound work on very large scrollbacks.
///
/// Column mapping: a width-2 glyph (CJK/emoji) occupies two cells but
/// [BufferLine.getText] emits one character for it, so a naive char-offset
/// match would land highlights on the wrong cell after any preceding wide
/// glyph. We therefore walk cells directly and map each emitted character back
/// to its starting cell column.
class TerminalSearch {
  TerminalSearch(this.terminal);

  final Terminal terminal;

  /// Maximum matches collected per query, to keep highlighting responsive on
  /// huge buffers. The counter surfaces how many were truncated.
  static const maxMatches = 500;

  /// Searches the buffer for [query].
  ///
  /// When [regex] is true, [query] is compiled as a [RegExp] (honouring
  /// [caseSensitive]); otherwise it is a literal substring match. An invalid
  /// regex returns an empty result rather than throwing. Returns the matches
  /// plus [truncated] (true if [maxMatches] was hit).
  SearchResult find(
    String query, {
    bool caseSensitive = false,
    bool regex = false,
  }) {
    if (query.isEmpty) return const SearchResult(matches: [], truncated: false);

    RegExp? pattern;
    if (regex) {
      try {
        pattern = RegExp(query, caseSensitive: caseSensitive);
      } on FormatException {
        return const SearchResult(matches: [], truncated: false);
      }
    }
    final needle = caseSensitive ? query : query.toLowerCase();

    final buffer = terminal.buffer;
    final matches = <SearchMatch>[];
    var truncated = false;

    for (var y = 0; y < buffer.height; y++) {
      final line = buffer.lines[y];
      final (text, cellOf, widthOf) = _lineText(line, buffer.viewWidth);
      if (text.isEmpty) continue;

      // Records a [charStart, charEnd) match as cell columns on this line.
      void record(int charStart, int charEnd) {
        if (matches.length >= maxMatches) {
          truncated = true;
          return;
        }
        final cs = cellOf[charStart];
        final ce = cellOf[charEnd - 1] + widthOf[charEnd - 1];
        matches.add(SearchMatch(lineIndex: y, colStart: cs, colEnd: ce));
      }

      if (pattern != null) {
        for (final m in pattern.allMatches(text)) {
          record(m.start, m.end);
          if (truncated) break;
        }
      } else {
        final hay = caseSensitive ? text : text.toLowerCase();
        var from = 0;
        while (true) {
          final idx = hay.indexOf(needle, from);
          if (idx == -1) break;
          record(idx, idx + needle.length);
          if (truncated) break;
          from = idx + 1;
        }
      }
      if (truncated) break;
    }
    return SearchResult(matches: matches, truncated: truncated);
  }

  /// Walks the cells of [line] (0..[viewWidth]) building the visible text and
  /// two parallel arrays: [cellOf[k]] = the starting cell column of the k-th
  /// emitted character, [widthOf[k]] = its cell width (1 or 2). Continuation
  /// cells of wide glyphs (codePoint 0) are skipped so there is one entry per
  /// visible character.
  (String, List<int>, List<int>) _lineText(BufferLine line, int viewWidth) {
    final buf = StringBuffer();
    final cellOf = <int>[];
    final widthOf = <int>[];
    for (var i = 0; i < viewWidth; i++) {
      final cp = line.getCodePoint(i);
      if (cp == 0) continue; // empty cell or wide-glyph continuation
      buf.writeCharCode(cp);
      cellOf.add(i);
      widthOf.add(line.getWidth(i));
    }
    return (buf.toString(), cellOf, widthOf);
  }
}

class SearchResult {
  final List<SearchMatch> matches;
  final bool truncated;

  const SearchResult({required this.matches, required this.truncated});
}
