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
    with AutomaticKeepAliveClientMixin {
  late final KeyboardVisibilityController _keyboardController;
  late final StreamSubscription<bool> _keyboardSubscription;
  late final TerminalController _terminalController;
  bool _isKeyboardVisible = false;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _keyboardSubscription.cancel();
    _terminalController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
          child: TerminalView(widget.terminal, controller: _terminalController),
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
