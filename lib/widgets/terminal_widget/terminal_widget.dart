import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:xterm/xterm.dart';
import '../../providers/settings_provider.dart';
import '../virtual_keyboard.dart';

class TerminalWidget extends ConsumerStatefulWidget {
  final Terminal terminal;

  const TerminalWidget({super.key, required this.terminal});

  @override
  ConsumerState<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends ConsumerState<TerminalWidget>
    with WidgetsBindingObserver {
  // NOTE: no AutomaticKeepAliveClientMixin here — keep-alive only functions
  // under keep-alive-aware parents (IndexedStack/slivers), and this widget is
  // built in a plain subtree, so the mixin was dead code.

  late final ScrollController _scrollController;
  bool _pinnedToBottom = true;
  late final KeyboardVisibilityController _keyboardController;
  late final StreamSubscription<bool> _keyboardSubscription;
  late final TerminalController _terminalController;
  late final FocusNode _focusNode;
  bool _isKeyboardVisible = false;

  /// Keep the viewport pinned to the live screen. Buffer-clearing sequences
  /// (cls/clear via ConPTY) append blank lines to the scrollback, which grows
  /// maxScrollExtent without the render layer's offset following — the view
  /// then sits a row or two above the real bottom and every new line looks
  /// displaced even though the buffer cursor is correct. When the user
  /// scrolls up we stop pinning; returning to the bottom resumes.
  void _onScroll() {
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    _pinnedToBottom =
        _scrollController.offset >= position.maxScrollExtent - 2;
  }

  void _pinToBottom() {
    if (!_pinnedToBottom || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.maxScrollExtent > 0 &&
          _scrollController.offset < position.maxScrollExtent - 2) {
        _scrollController.jumpTo(position.maxScrollExtent);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    widget.terminal.addListener(_pinToBottom);
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
  }

  /// Test hook: the scroll position of the terminal viewport.
  @visibleForTesting
  ScrollController get debugScrollController => _scrollController;

  @override
  void didUpdateWidget(TerminalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_pinToBottom);
      widget.terminal.addListener(_pinToBottom);
      _pinToBottom();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardSubscription.cancel();
    widget.terminal.removeListener(_pinToBottom);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _terminalController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

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

    return Column(
      children: [
        Expanded(
          child: TerminalView(
            widget.terminal,
            controller: _terminalController,
            focusNode: _focusNode,
            scrollController: _scrollController,
            // The terminal is the screen's primary content — take keyboard
            // focus on launch and session switches, otherwise keystrokes go
            // nowhere until the user happens to click inside it.
            autofocus: true,
            // Windows' TextInputPlugin silently drops printable-character
            // insertions for the hidden text field xterm attaches, leaving
            // special keys (Enter) working while plain typing is dead. On
            // desktop, take characters straight from hardware key events;
            // mobile keeps the text-input path for the soft keyboard.
            hardwareKeyboardOnly:
                !kIsWeb && (Platform.isWindows || Platform.isLinux),
          ),
        ),
        if (showKeyboard)
          VirtualKeyboardBar(
            terminal: widget.terminal,
            controller: _terminalController,
          ),
      ],
    );
  }
}
