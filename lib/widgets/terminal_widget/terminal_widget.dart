import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../virtual_keyboard.dart';

class TerminalWidget extends StatefulWidget {
  final Terminal terminal;

  const TerminalWidget({super.key, required this.terminal});

  @override
  State<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<TerminalWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return Column(
      children: [
        Expanded(child: TerminalView(widget.terminal)),
        if (isKeyboardVisible) VirtualKeyboardBar(terminal: widget.terminal),
      ],
    );
  }
}
