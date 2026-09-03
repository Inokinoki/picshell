import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/services/terminal_search.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('TerminalSearch', () {
    test('finds substring matches across lines with column offsets', () {
      final terminal = Terminal(maxLines: 1000);
      // CR+LF so each line starts at column 0 (plain LF keeps the column).
      terminal.write('foo bar\r\nbaz foo\r\n');
      final search = TerminalSearch(terminal);

      final result = search.find('foo');
      expect(result.matches.length, 2);
      expect(result.matches[0].colStart, 0);
      expect(result.matches[0].colEnd, 3);
      expect(result.matches[1].colStart, 4);
      expect(result.matches[1].colEnd, 7);
      expect(result.matches[1].lineIndex, greaterThan(result.matches[0].lineIndex));
    });

    test('empty query returns no matches', () {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('hello world');
      final result = TerminalSearch(terminal).find('');
      expect(result.matches, isEmpty);
    });

    test('default search is case-insensitive', () {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('Foo FOO foo\n');
      final result = TerminalSearch(terminal).find('fOo');
      expect(result.matches.length, 3);
    });

    test('case-sensitive search respects casing', () {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('Foo foo FOO\n');
      final cs = TerminalSearch(terminal).find('foo', caseSensitive: true);
      expect(cs.matches.length, 1);
      expect(cs.matches[0].colStart, 4);
    });

    test('regex mode matches patterns', () {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('bar baz boz\n');
      final result =
          TerminalSearch(terminal).find('ba[rz]', regex: true);
      expect(result.matches.length, 2); // bar, baz
      expect(result.matches[0].colStart, 0);
      expect(result.matches[1].colStart, 4);
    });

    test('overlapping/adjacent matches are all found', () {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('aaa\n');
      final result = TerminalSearch(terminal).find('a');
      expect(result.matches.length, 3);
    });

    test('caps the result set and reports truncation', () {
      final terminal = Terminal(maxLines: 10000);
      // Each line has 10 'x' tokens → many matches for 'x'.
      final buf = StringBuffer();
      for (var i = 0; i < 200; i++) {
        buf.write('x x x x x x x x x x\n');
      }
      terminal.write(buf.toString());
      final result = TerminalSearch(terminal).find('x');
      expect(result.matches.length, lessThanOrEqualTo(TerminalSearch.maxMatches));
      expect(result.truncated, isTrue);
    });

    test('wide glyphs map to cell columns, not character offsets', () {
      // 你 is East-Asian Wide → occupies 2 cells; 'foo' then starts at cell 2,
      // not character offset 1.
      final terminal = Terminal(maxLines: 1000);
      terminal.write('你foo\n');
      final result = TerminalSearch(terminal).find('foo');
      expect(result.matches.length, 1);
      expect(result.matches[0].colStart, 2, reason: 'cell column after a wide glyph');
      expect(result.matches[0].colEnd, 5);
    });

    test('invalid regex returns an empty result instead of throwing', () {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('hello\n');
      expect(
        () => TerminalSearch(terminal).find('(', regex: true),
        returnsNormally,
      );
      expect(TerminalSearch(terminal).find('(', regex: true).matches, isEmpty);
      expect(TerminalSearch(terminal).find('[a-', regex: true).matches, isEmpty);
    });

    test('zero-width regex matches are skipped, not crashed on', () {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('hello\n');
      for (final pattern in ['x*', 'o*', '\\b', '^', '\$', '']) {
        expect(
          () => TerminalSearch(terminal).find(pattern, regex: true),
          returnsNormally,
          reason: 'pattern "$pattern" must not throw',
        );
      }
      // Zero-width matches have no cell span to highlight, so none are
      // recorded; non-zero-width parts of such patterns still match.
      expect(
          TerminalSearch(terminal).find('x*', regex: true).matches, isEmpty);
      final mixed =
          TerminalSearch(terminal).find('l+', regex: true).matches;
      expect(mixed.length, 1); // 'll' in 'hello'
      expect(mixed[0].colEnd, greaterThan(mixed[0].colStart));
    });

    test('multiLine anchors match at the start of every line', () {
      final terminal = Terminal(maxLines: 1000);
      terminal.write('ab\r\ncd\r\n');
      // Without multiLine, '^' would only match the first line.
      final result = TerminalSearch(terminal).find('^', regex: true);
      // Zero-width matches are skipped, so use a pattern that consumes a char.
      final result2 = TerminalSearch(terminal).find('^.', regex: true);
      expect(result2.matches.length, 2);
      expect(result2.matches.every((m) => m.colStart == 0), isTrue);
      expect(result.matches, isEmpty);
    });
  });
}
