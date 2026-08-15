import 'dart:async';
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
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late final KeyboardVisibilityController _keyboardController;
  late final StreamSubscription<bool> _keyboardSubscription;
  late final TerminalController _terminalController;
  late final FocusNode _focusNode;
  bool _isKeyboardVisible = false;

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardSubscription.cancel();
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
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final settings = ref.watch(settingsProvider);

    // Theme/style are TerminalView params and hot-swap via updateRenderObject
    // (no Terminal re-creation). An empty fontFamily falls back to xterm's
    // platform default ('monospace' + its CJK/emoji fallback chain).
    final textStyle = settings.fontFamily.isEmpty
        ? TerminalStyle(
            fontSize: settings.fontSize,
            height: settings.lineHeight,
          )
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

    return Column(
      children: [
        Expanded(
          child: TerminalView(
            widget.terminal,
            controller: _terminalController,
            focusNode: _focusNode,
            theme: settings.palette.theme,
            keyboardAppearance: settings.palette.keyboardBrightness,
            textStyle: textStyle,
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
