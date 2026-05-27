import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/floating_image_provider.dart';
import 'floating_image_widget.dart';

class FloatingImageOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const FloatingImageOverlay({super.key, required this.child});

  @override
  ConsumerState<FloatingImageOverlay> createState() =>
      _FloatingImageOverlayState();
}

class _FloatingImageOverlayState extends ConsumerState<FloatingImageOverlay> {
  final List<OverlayEntry> _overlayEntries = [];

  @override
  void dispose() {
    for (final entry in _overlayEntries) {
      entry.remove();
    }
    _overlayEntries.clear();
    super.dispose();
  }

  void _syncOverlays(List<dynamic> images) {
    final overlay = Overlay.of(context);

    final currentIds = images
        .where((img) => !img.minimized)
        .map((img) => img.id)
        .toList();

    final entriesToRemove = _overlayEntries
        .where(
          (entry) =>
              !currentIds.contains((entry as _ImageOverlayEntry).imageId),
        )
        .toList();

    for (final entry in entriesToRemove) {
      entry.remove();
      _overlayEntries.remove(entry);
    }

    for (final img in images) {
      if (img.minimized) continue;
      final exists = _overlayEntries.any(
        (e) => (e as _ImageOverlayEntry).imageId == img.id,
      );
      if (!exists) {
        final entry = _ImageOverlayEntry(
          imageId: img.id,
          builder: (context) => FloatingImageWidget(image: img),
        );
        _overlayEntries.add(entry);
        overlay.insert(entry);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = ref.watch(floatingImagesProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncOverlays(images);
    });

    return widget.child;
  }
}

class _ImageOverlayEntry extends OverlayEntry {
  final String imageId;

  _ImageOverlayEntry({required this.imageId, required super.builder});
}
