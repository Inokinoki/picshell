import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:xterm/xterm.dart';
import '../../providers/settings_provider.dart';
import '../../services/terminal_search.dart';
import '../virtual_keyboard.dart';

class TerminalWidget extends ConsumerStatefulWidget {
  final Terminal terminal;

  const TerminalWidget({super.key, required this.terminal});

  @override
  ConsumerState<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends ConsumerState<TerminalWidget>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late final KeyboardVisibilityController _keyboardController;
  late final StreamSubscription<bool> _keyboardSubscription;
  late final TerminalController _terminalController;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;
  late final TextEditingController _searchFieldController;
  late final FocusNode _searchFieldFocus;
  late final TerminalSearch _search;
  bool _isKeyboardVisible = false;

  // Search state.
  bool _searchVisible = false;
  String _query = '';
  bool _caseSensitive = false;
  bool _regex = false;
  SearchResult _result = const SearchResult(matches: [], truncated: false);
  int _current = -1; // index into _result.matches, -1 when none
  List<TerminalHighlight> _highlights = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keyboardController = KeyboardVisibilityController();
    _isKeyboardVisible = _keyboardController.isVisible;
    _keyboardSubscription = _keyboardController.onChange.listen((visible) {
      if (mounted) {
        setState(() {
          _isKeyboardVisible = visible;
        });
      }
    });
    _terminalController = TerminalController();
    _focusNode = FocusNode();
    _scrollController = ScrollController();
    _searchFieldController = TextEditingController();
    // Esc closes the search even while the field has focus (the terminal's
    // onKeyEvent does not fire once the field grabs focus).
    _searchFieldFocus = FocusNode(onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _closeSearch();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    });
    _search = TerminalSearch(widget.terminal);
    // Refresh the search while the bar is open so results stay correct as new
    // output shifts line indices (CellAnchors track content, but our stored
    // lineIndex snapshots go stale once scrollback wraps).
    widget.terminal.addListener(_onTerminalChanged);
  }

  void _onTerminalChanged() {
    if (!_searchVisible || _query.isEmpty) return;
    _scheduleSearch();
  }

  /// Disposes every highlight AND the two CellAnchors it owns. CellAnchors are
  /// NOT owned by TerminalHighlight, so disposing only the highlight leaks them
  /// (they accumulate in BufferLine._anchors and slow every text mutation).
  void _disposeHighlights() {
    for (final h in _highlights) {
      h.p1.dispose();
      h.p2.dispose();
      h.dispose();
    }
    _highlights = [];
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _runSearch);
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalChanged);
    WidgetsBinding.instance.removeObserver(this);
    _keyboardSubscription.cancel();
    _debounce?.cancel();
    _disposeHighlights();
    _terminalController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _searchFieldController.dispose();
    _searchFieldFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _focusNode.requestFocus();
    }
  }

  @override
  bool get wantKeepAlive => true;

  /// Intercepts Ctrl+F (open search) and Esc (close) before the terminal input
  /// handler sees them. Everything else passes through unchanged.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (HardwareKeyboard.instance.isControlPressed &&
        key == LogicalKeyboardKey.keyF) {
      _openSearch();
      return KeyEventResult.handled;
    }
    if (_searchVisible && key == LogicalKeyboardKey.escape) {
      _closeSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openSearch() {
    setState(() => _searchVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFieldFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _debounce?.cancel();
    _disposeHighlights();
    setState(() {
      _searchVisible = false;
      _query = '';
      _searchFieldController.clear();
      _result = const SearchResult(matches: [], truncated: false);
      _current = -1;
    });
    _focusNode.requestFocus();
  }

  void _onQueryChanged(String value) {
    _query = value;
    _scheduleSearch();
  }

  void _runSearch() {
    final result = _search.find(_query,
        caseSensitive: _caseSensitive, regex: _regex);
    setState(() {
      _result = result;
      _current = result.matches.isEmpty ? -1 : 0;
    });
    _applyHighlights();
    if (_current >= 0) _scrollToCurrent();
  }

  /// Recreates every highlight (the background colour distinguishes the
  /// current match). Called when the result set or current index changes; cheap
  /// enough at the [TerminalSearch.maxMatches] cap for a user-initiated action.
  void _applyHighlights() {
    _disposeHighlights();
    final buffer = widget.terminal.buffer;
    // Follow the selected palette's theme so a future scheme can override
    // the search-hit colours (they are currently shared constants).
    final theme = ref.read(settingsProvider).palette.theme;
    final bg = theme.searchHitBackground;
    final bgCur = theme.searchHitBackgroundCurrent;
    for (var i = 0; i < _result.matches.length; i++) {
      final m = _result.matches[i];
      // Skip matches whose line has scrolled out of the buffer entirely.
      if (m.lineIndex < 0 || m.lineIndex >= buffer.height) continue;
      final a1 = buffer.createAnchor(m.colStart, m.lineIndex);
      final a2 = buffer.createAnchor(m.colEnd, m.lineIndex);
      _highlights.add(_terminalController.highlight(
        p1: a1,
        p2: a2,
        color: i == _current ? bgCur : bg,
      ));
    }
  }

  void _goto(int index) {
    if (_result.matches.isEmpty) return;
    setState(() {
      _current = (index % _result.matches.length + _result.matches.length) %
          _result.matches.length;
    });
    _applyHighlights();
    _scrollToCurrent();
  }

  /// Scrolls so the current match is centred. Derives line height from the
  /// scrollable extent (maxScrollExtent == (height − viewHeight) × lineHeight)
  /// to avoid reaching into the RenderTerminal.
  void _scrollToCurrent() {
    if (_current < 0 || !_scrollController.hasClients) return;
    final m = _result.matches[_current];
    final buffer = widget.terminal.buffer;
    final pos = _scrollController.position;
    final scrollableLines =
        (buffer.height - buffer.viewHeight).clamp(1, 1 << 30);
    final lineHeight = pos.maxScrollExtent / scrollableLines;
    final target = (m.lineIndex - buffer.viewHeight / 2) * lineHeight;
    pos.jumpTo(target.clamp(0.0, pos.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final settings = ref.watch(settingsProvider);

    // Theme/style are TerminalView params and hot-swap via updateRenderObject
    // (no Terminal re-creation). An empty fontFamily falls back to xterm's
    // platform default ('monospace' + its CJK/emoji fallback chain).
    final textStyle = settings.fontFamily.isEmpty
        ? TerminalStyle(fontSize: settings.fontSize, height: settings.lineHeight)
        : TerminalStyle(
            fontFamily: settings.fontFamily,
            fontSize: settings.fontSize,
            height: settings.lineHeight,
          );

    bool showKeyboard;
    switch (settings.keyboardBarMode) {
      case KeyboardBarMode.auto:
        showKeyboard = _isKeyboardVisible;
        break;
      case KeyboardBarMode.always:
        showKeyboard = true;
        break;
      case KeyboardBarMode.hidden:
        showKeyboard = false;
        break;
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: TerminalView(
                widget.terminal,
                controller: _terminalController,
                focusNode: _focusNode,
                theme: settings.palette.theme,
                textStyle: textStyle,
                scrollController: _scrollController,
                onKeyEvent: _onKey,
              ),
            ),
            if (showKeyboard)
              VirtualKeyboardBar(
                terminal: widget.terminal,
                controller: _terminalController,
              ),
          ],
        ),
        if (_searchVisible)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildSearchBar(),
          ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final count = _result.matches.isEmpty
        ? (_query.isEmpty ? '' : '0/0')
        : '${_current + 1}/${_result.matches.length}${_result.truncated ? '+' : ''}';
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.search, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _searchFieldController,
                  focusNode: _searchFieldFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search (Ctrl+F)',
                    border: InputBorder.none,
                  ),
                  onChanged: _onQueryChanged,
                  onSubmitted: (_) => _runSearch(),
                ),
              ),
              IconButton(
                tooltip: 'Match case',
                iconSize: 18,
                isSelected: _caseSensitive,
                selectedIcon: const Icon(Icons.text_fields),
                icon: const Icon(Icons.text_fields_outlined),
                onPressed: () {
                  setState(() => _caseSensitive = !_caseSensitive);
                  _runSearch();
                },
              ),
              IconButton(
                tooltip: 'Regex',
                iconSize: 18,
                isSelected: _regex,
                selectedIcon: const Icon(Icons.code),
                icon: const Icon(Icons.code_off),
                onPressed: () {
                  setState(() => _regex = !_regex);
                  _runSearch();
                },
              ),
              if (count.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(count, style: const TextStyle(fontSize: 13)),
                ),
              IconButton(
                tooltip: 'Previous match',
                iconSize: 20,
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed:
                    _result.matches.isEmpty ? null : () => _goto(_current - 1),
              ),
              IconButton(
                tooltip: 'Next match',
                iconSize: 20,
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed:
                    _result.matches.isEmpty ? null : () => _goto(_current + 1),
              ),
              IconButton(
                tooltip: 'Close (Esc)',
                iconSize: 20,
                icon: const Icon(Icons.close),
                onPressed: _closeSearch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
