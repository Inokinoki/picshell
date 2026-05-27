import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final settings = ref.watch(settingsProvider);
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    bool showKeyboard;
    switch (settings.keyboardBarMode) {
      case KeyboardBarMode.auto:
        showKeyboard = isKeyboardVisible;
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
        Expanded(child: TerminalView(widget.terminal)),
        if (showKeyboard) VirtualKeyboardBar(terminal: widget.terminal),
      ],
    );
  }
}
