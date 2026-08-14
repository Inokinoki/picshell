import 'package:flutter/material.dart';

/// Teal-accent section label shared across settings sections. Extracted from
/// the settings screen so feature-specific sections (appearance, etc.) reuse
/// the same styling without duplicating the private widget.
class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.tealAccent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
