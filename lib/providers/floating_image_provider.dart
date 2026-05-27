import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/floating_image.dart';

final floatingImagesProvider =
    StateNotifierProvider<FloatingImagesNotifier, List<FloatingImage>>(
      (ref) => FloatingImagesNotifier(),
    );

class FloatingImagesNotifier extends StateNotifier<List<FloatingImage>> {
  FloatingImagesNotifier() : super([]);

  int _imageCounter = 0;

  void addImage(FloatingImage image) {
    _imageCounter++;
    final offset = Offset(
      50.0 + (_imageCounter % 5) * 30.0,
      50.0 + (_imageCounter % 5) * 30.0,
    );
    image.position = offset;
    state = [...state, image];
  }

  void removeImage(String id) {
    state = state.where((img) => img.id != id).toList();
  }

  void toggleMinimize(String id) {
    state = [
      for (final img in state)
        if (img.id == id)
          FloatingImage(
            id: img.id,
            rawBytes: img.rawBytes,
            name: img.name,
            position: img.position,
            size: img.size,
            minimized: !img.minimized,
            requestedWidth: img.requestedWidth,
            requestedHeight: img.requestedHeight,
          )
        else
          img,
    ];
  }

  void updatePosition(String id, Offset newPosition) {
    state = [
      for (final img in state)
        if (img.id == id)
          FloatingImage(
            id: img.id,
            rawBytes: img.rawBytes,
            name: img.name,
            position: newPosition,
            size: img.size,
            minimized: img.minimized,
            requestedWidth: img.requestedWidth,
            requestedHeight: img.requestedHeight,
          )
        else
          img,
    ];
  }

  void updateSize(String id, Size newSize) {
    state = [
      for (final img in state)
        if (img.id == id)
          FloatingImage(
            id: img.id,
            rawBytes: img.rawBytes,
            name: img.name,
            position: img.position,
            size: newSize,
            minimized: img.minimized,
            requestedWidth: img.requestedWidth,
            requestedHeight: img.requestedHeight,
          )
        else
          img,
    ];
  }
}
