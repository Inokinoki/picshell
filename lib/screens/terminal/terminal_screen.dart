import 'package:flutter/material.dart';
import '../../services/ssh_service.dart';
import '../../widgets/terminal_widget/terminal_widget.dart';

class TerminalScreen extends StatelessWidget {
  final SshService sshService;

  const TerminalScreen({super.key, required this.sshService});

  @override
  Widget build(BuildContext context) {
    return TerminalWidget(sshService: sshService);
  }
}
