import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/floating_image.dart';
import '../providers/floating_image_provider.dart';

class FloatingImageWidget extends ConsumerStatefulWidget {
  final FloatingImage image;

  const FloatingImageWidget({super.key, required this.image});

  @override
  ConsumerState<FloatingImageWidget> createState() =>
      _FloatingImageWidgetState();
}

class _FloatingImageWidgetState extends ConsumerState<FloatingImageWidget> {
  ui.Image? _decodedImage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void didUpdateWidget(FloatingImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.id != widget.image.id) {
      _decodeImage();
    }
  }

  Future<void> _decodeImage() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final codec = await ui.instantiateImageCodec(widget.image.rawBytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _decodedImage = frame.image;
          _isLoading = false;
          if (widget.image.size == Size.zero) {
            var size = Size(
              frame.image.width.toDouble(),
              frame.image.height.toDouble(),
            );
            final view = View.of(context);
            final maxW = view.physicalSize.width / view.devicePixelRatio * 0.8;
            final maxH = view.physicalSize.height / view.devicePixelRatio * 0.8;
            if (size.width > maxW || size.height > maxH) {
              final scaleW = maxW / size.width;
              final scaleH = maxH / size.height;
              final scale = scaleW < scaleH ? scaleW : scaleH;
              size = Size(size.width * scale, size.height * scale);
            }
            ref
                .read(floatingImagesProvider.notifier)
                .updateSize(widget.image.id, size);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = widget.image;
    final size = img.size != Size.zero ? img.size : const Size(200, 200);

    return Positioned(
      left: img.position.dx,
      top: img.position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          ref
              .read(floatingImagesProvider.notifier)
              .updatePosition(img.id, img.position + details.delta);
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade900,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(
                      img.name,
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        ref
                            .read(floatingImagesProvider.notifier)
                            .toggleMinimize(img.id);
                      },
                      child: Icon(
                        Icons.minimize,
                        size: 14,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        ref
                            .read(floatingImagesProvider.notifier)
                            .removeImage(img.id);
                      },
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoading)
                SizedBox(
                  width: size.width,
                  height: size.height,
                  child: const Center(child: CircularProgressIndicator()),
                )
              else if (_decodedImage != null)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(8),
                  ),
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: RawImage(image: _decodedImage),
                  ),
                )
              else
                SizedBox(
                  width: size.width,
                  height: size.height,
                  child: const Center(child: Text('Failed to load')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
