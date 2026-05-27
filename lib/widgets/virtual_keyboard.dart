import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

class VirtualKeyboardBar extends StatefulWidget {
  final Terminal terminal;
  final TerminalController? controller;

  const VirtualKeyboardBar({
    super.key,
    required this.terminal,
    this.controller,
  });

  @override
  State<VirtualKeyboardBar> createState() => _VirtualKeyboardBarState();
}

class _VirtualKeyboardBarState extends State<VirtualKeyboardBar> {
  bool _ctrlActive = false;
  bool _altActive = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: const Color(0xFF2D2D2D),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        children: [
          _buildKey('Esc', onTap: _sendEsc),
          _buildKey('Tab', onTap: _sendTab),
          _buildModKey('Ctrl', _ctrlActive, () {
            setState(() => _ctrlActive = !_ctrlActive);
          }),
          _buildModKey('Alt', _altActive, () {
            setState(() => _altActive = !_altActive);
          }),
          const SizedBox(width: 8),
          _buildKey('↑', onTap: () => _sendArrow(TerminalKey.arrowUp)),
          _buildKey('↓', onTap: () => _sendArrow(TerminalKey.arrowDown)),
          _buildKey('←', onTap: () => _sendArrow(TerminalKey.arrowLeft)),
          _buildKey('→', onTap: () => _sendArrow(TerminalKey.arrowRight)),
          const SizedBox(width: 8),
          _buildKey('Copy', icon: Icons.copy, onTap: _copySelection),
          _buildKey('Paste', icon: Icons.paste, onTap: _paste),
          const SizedBox(width: 8),
          _buildKey('|', onTap: () => _sendChar('|')),
          _buildKey('~', onTap: () => _sendChar('~')),
          _buildKey('-', onTap: () => _sendChar('-')),
          _buildKey('_', onTap: () => _sendChar('_')),
          _buildKey('/', onTap: () => _sendChar('/')),
        ],
      ),
    );
  }

  Widget _buildKey(
    String label, {
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: const Color(0xFF404040),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: icon != null
                ? Icon(icon, color: Colors.white, size: 18)
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildModKey(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: active ? Colors.teal.shade700 : const Color(0xFF404040),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white70,
                fontSize: 14,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _sendEsc() {
    widget.terminal.keyInput(TerminalKey.escape);
    _resetModifiers();
  }

  void _sendTab() {
    widget.terminal.textInput('\t');
    _resetModifiers();
  }

  void _sendArrow(TerminalKey key) {
    widget.terminal.keyInput(key, ctrl: _ctrlActive, alt: _altActive);
    _resetModifiers();
  }

  void _sendChar(String char) {
    if (_ctrlActive) {
      final code = char.toLowerCase().codeUnitAt(0);
      if (code >= 97 && code <= 122) {
        widget.terminal.textInput(String.fromCharCode(code - 96));
      } else {
        widget.terminal.textInput(char);
      }
    } else {
      widget.terminal.textInput(char);
    }
    _resetModifiers();
  }

  void _copySelection() {
    final controller = widget.controller;
    if (controller == null) return;

    final selection = controller.selection;
    if (selection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Long press and drag to select text first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final buffer = widget.terminal.buffer;
    final text = StringBuffer();

    for (var y = selection.begin.y; y <= selection.end.y; y++) {
      final line = buffer.lines[y];

      final startX = y == selection.begin.y ? selection.begin.x : 0;
      final endX = y == selection.end.y ? selection.end.x : line.length - 1;

      for (var x = startX; x <= endX; x++) {
        final charCode = line.getCodePoint(x);
        if (charCode != 0) {
          text.writeCharCode(charCode);
        }
      }

      if (y < selection.end.y) {
        text.write('\n');
      }
    }

    final selectedText = text.toString();
    if (selectedText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: selectedText));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied ${selectedText.length} characters'),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    controller.clearSelection();
    _resetModifiers();
  }

  void _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      widget.terminal.textInput(data!.text!);
    }
    _resetModifiers();
  }

  void _resetModifiers() {
    if (_ctrlActive || _altActive) {
      setState(() {
        _ctrlActive = false;
        _altActive = false;
      });
    }
  }
}
