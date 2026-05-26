import 'dart:async';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../../services/ssh_service.dart';

class TerminalWidget extends StatefulWidget {
  final SshService sshService;

  const TerminalWidget({super.key, required this.sshService});

  @override
  State<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<TerminalWidget> {
  late final Terminal terminal;
  StreamSubscription<String>? _outputSubscription;

  @override
  void initState() {
    super.initState();
    terminal = Terminal(
      maxLines: 10000,
      onOutput: (data) {
        widget.sshService.writeToTerminal(data);
      },
      onResize: (width, height, pixelWidth, pixelHeight) {
        widget.sshService.resizeTerminal(width, height);
      },
    );

    _outputSubscription = widget.sshService.output.listen((data) {
      terminal.write(data);
    });
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalView(terminal);
  }
}
