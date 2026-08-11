import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/floating_image.dart';

final floatingImagesProvider =
    StateNotifierProvider<FloatingImagesNotifier, List<FloatingImage>>(
      (ref) => FloatingImagesNotifier(),
    );

/// Maximum number of non-minimized floating images kept on screen. Older
/// images are evicted (LRU) once this is exceeded. Minimized images also
/// count toward [maxTotalBytes] since their bytes still live in memory.
const maxImages = 8;

/// Soft cap on the total decoded bytes held by the provider. Once exceeded,
/// the oldest images are dropped until the sum fits.
const maxTotalBytes = 64 * 1024 * 1024; // 64 MiB

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
    _enforceLimits();
  }

  /// Evicts the oldest images until both [maxImages] and [maxTotalBytes] are
  /// satisfied. Only non-minimized images are evicted by the count limit (a
  /// minimized image is a deliberate user pin); the byte limit, however, may
  /// drop minimized images too, since they still hold memory.
  void _enforceLimits() {
    var current = state;

    // 1) Count limit: drop oldest non-minimized until we have <= maxImages.
    while (current.length > maxImages) {
      final idx = current.indexWhere((img) => !img.minimized);
      if (idx == -1) break; // all remaining are minimized — stop.
      current = [...current..removeAt(idx)];
    }

    // 2) Byte limit: drop oldest overall until total <= maxTotalBytes.
    int totalBytes() =>
        current.fold<int>(0, (sum, img) => sum + img.rawBytes.length);
    while (totalBytes() > maxTotalBytes && current.isNotEmpty) {
      current = current.sublist(1);
    }

    state = current;
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
            scale: img.scale,
            inline: img.inline,
            preserveAspectRatio: img.preserveAspectRatio,
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
            scale: img.scale,
            inline: img.inline,
            preserveAspectRatio: img.preserveAspectRatio,
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
            scale: img.scale,
            inline: img.inline,
            preserveAspectRatio: img.preserveAspectRatio,
          )
        else
          img,
    ];
  }

  /// Updates the user zoom scale, clamped to [0.25, 4.0] (25%–400%).
  void updateScale(String id, double newScale) {
    final clamped = newScale.clamp(0.25, 4.0).toDouble();
    state = [
      for (final img in state)
        if (img.id == id)
          FloatingImage(
            id: img.id,
            rawBytes: img.rawBytes,
            name: img.name,
            position: img.position,
            size: img.size,
            minimized: img.minimized,
            requestedWidth: img.requestedWidth,
            requestedHeight: img.requestedHeight,
            scale: clamped,
            inline: img.inline,
            preserveAspectRatio: img.preserveAspectRatio,
          )
        else
          img,
    ];
  }
}
