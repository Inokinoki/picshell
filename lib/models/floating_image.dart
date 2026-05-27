import 'dart:typed_data';
import 'package:flutter/painting.dart';

class FloatingImage {
  final String id;
  final Uint8List rawBytes;
  final String name;
  Offset position;
  Size size;
  bool minimized;
  final int? requestedWidth;
  final int? requestedHeight;

  FloatingImage({
    required this.id,
    required this.rawBytes,
    required this.name,
    this.position = Offset.zero,
    this.size = Size.zero,
    this.minimized = false,
    this.requestedWidth,
    this.requestedHeight,
  });
}
