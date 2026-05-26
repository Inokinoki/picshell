import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../../widgets/terminal_widget/terminal_widget.dart';

class TerminalScreen extends StatelessWidget {
  final Terminal terminal;

  const TerminalScreen({super.key, required this.terminal});

  @override
  Widget build(BuildContext context) {
    return TerminalWidget(terminal: terminal);
  }
}
