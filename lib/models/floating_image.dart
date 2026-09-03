import 'dart:typed_data';
import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart' show Iterm2Dimension;

class FloatingImage {
  final String id;
  final Uint8List rawBytes;
  final String name;
  Offset position;
  Size size;
  bool minimized;

  /// Size requests carried by the iTerm2 sequence (`width=`/`height=`),
  /// including their unit — a bare `N` counts terminal cells, `Npx` pixels,
  /// `N%` percent of the viewport.
  final Iterm2Dimension? requestedWidth;
  final Iterm2Dimension? requestedHeight;
  double scale;
  final bool inline;
  final bool preserveAspectRatio;

  FloatingImage({
    required this.id,
    required this.rawBytes,
    required this.name,
    this.position = Offset.zero,
    this.size = Size.zero,
    this.minimized = false,
    this.requestedWidth,
    this.requestedHeight,
    this.scale = 1.0,
    this.inline = true,
    this.preserveAspectRatio = true,
  });
}
