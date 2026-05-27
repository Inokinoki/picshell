import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/floating_image_provider.dart';
import 'floating_image_widget.dart';

class FloatingImageOverlay extends ConsumerWidget {
  final Widget child;

  const FloatingImageOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = ref.watch(floatingImagesProvider);
    final visibleImages = images.where((img) => !img.minimized).toList();

    return Stack(
      children: [
        child,
        for (final img in visibleImages)
          FloatingImageWidget(key: ValueKey(img.id), image: img),
      ],
    );
  }
}
