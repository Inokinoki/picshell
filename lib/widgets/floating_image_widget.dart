import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/floating_image.dart';
import '../providers/floating_image_provider.dart';

/// Singleton that tracks whether Option (macOS) or Alt (other) is held.
///
/// Listens to [HardwareKeyboard] globally so the state is correct even when
/// focus is elsewhere (e.g. the terminal). Used by [FloatingImageWidget] to
/// decide whether a scroll-wheel event should zoom or pass through.
///
/// Note: Cmd+scroll is intercepted by macOS for Mission Control / Spaces, so
/// we use Option/Alt instead which reaches the app reliably.
class ModifierTracker {
  ModifierTracker._();
  static final ModifierTracker instance = ModifierTracker._();

  bool _altHeld = false;

  bool get isZoomModifierHeld => _altHeld;

  /// Register once at app startup (idempotent).
  void init() {
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// For tests: reset tracked state without removing the handler.
  void reset() {
    _altHeld = false;
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.altLeft ||
          event.logicalKey == LogicalKeyboardKey.altRight) {
        _altHeld = true;
        debugPrint('[ModifierTracker] alt DOWN → held=$_altHeld');
      }
    } else if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.altLeft ||
          event.logicalKey == LogicalKeyboardKey.altRight) {
        _altHeld = false;
        debugPrint('[ModifierTracker] alt UP → held=$_altHeld');
      }
    }
    return false; // don't consume – let others handle too.
  }
}

/// Computes the initial display size honouring the iTerm2 protocol's
/// `width`/`height` request params when present, falling back to the decoded
/// pixel dimensions, then fitting to 80% of [viewport]. Pure function for
/// testability.
Size computeBaseDisplaySize({
  required int decodedWidth,
  required int decodedHeight,
  int? requestedWidth,
  int? requestedHeight,
  required Size viewport,
}) {
  Size size;
  if (requestedWidth != null && requestedHeight != null) {
    size = Size(requestedWidth.toDouble(), requestedHeight.toDouble());
  } else if (requestedWidth != null) {
    final ratio = decodedHeight / decodedWidth;
    size =
        Size(requestedWidth.toDouble(), requestedWidth.toDouble() * ratio);
  } else if (requestedHeight != null) {
    final ratio = decodedWidth / decodedHeight;
    size = Size(
        requestedHeight.toDouble() * ratio, requestedHeight.toDouble());
  } else {
    size = Size(decodedWidth.toDouble(), decodedHeight.toDouble());
  }
  final maxW = viewport.width * 0.8;
  final maxH = viewport.height * 0.8;
  if ((maxW > 0 && size.width > maxW) ||
      (maxH > 0 && size.height > maxH)) {
    final scaleW = maxW / size.width;
    final scaleH = maxH / size.height;
    final scale = scaleW < scaleH ? scaleW : scaleH;
    size = Size(size.width * scale, size.height * scale);
  }
  return size;
}

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

  /// Scale captured on gesture start, used to compute absolute scale from the
  /// relative `details.scale` and avoid drift across multiple callbacks.
  double _scaleAtGestureStart = 1.0;

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
        // Compute the base size outside setState so a viewport lookup failure
        // (e.g. in headless tests) doesn't corrupt the decoded-image state.
        Size? newSize;
        if (widget.image.size == Size.zero) {
          try {
            final view = View.of(context);
            newSize = computeBaseDisplaySize(
              decodedWidth: frame.image.width,
              decodedHeight: frame.image.height,
              requestedWidth: widget.image.requestedWidth,
              requestedHeight: widget.image.requestedHeight,
              viewport: Size(
                view.physicalSize.width / view.devicePixelRatio,
                view.physicalSize.height / view.devicePixelRatio,
              ),
            );
          } catch (_) {
            // Viewport unavailable (headless test): fall back to raw pixels.
            newSize = Size(frame.image.width.toDouble(),
                frame.image.height.toDouble());
          }
        }
        setState(() {
          _decodedImage = frame.image;
          _isLoading = false;
          if (newSize != null) {
            widget.image.size = newSize;
          }
        });
        if (newSize != null) {
          ref
              .read(floatingImagesProvider.notifier)
              .updateSize(widget.image.id, widget.image.size);
        }
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
    final baseSize = img.size != Size.zero ? img.size : const Size(200, 200);
    // Actual rendered size = base × user zoom scale.
    final renderSize =
        Size(baseSize.width * img.scale, baseSize.height * img.scale);

    return Positioned(
      left: img.position.dx,
      top: img.position.dy,
      // Listener captures the mouse wheel; translucent behaviour lets the
      // arena below also see plain scrolls so they reach the terminal. We zoom
      // only when a modifier (Cmd/Ctrl) is held, queried from the global
      // keyboard state (no focus dependency). GestureDetector handles drag
      // (single pointer) + pinch (two pointers).
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) {
            // Two-pronged modifier detection:
            // 1. ModifierTracker listens to HardwareKeyboard.addHandler and
            //    tracks key-down/up state manually (works in real apps).
            // 2. HardwareKeyboard.instance.logicalKeysPressed is the snapshot
            //    of currently-held keys (works in tests and as fallback).
            // We use Option/Alt (not Cmd/Ctrl) because macOS intercepts
            // Cmd+scroll for Mission Control / Spaces gestures.
            final tracker = ModifierTracker.instance;
            final pressed = HardwareKeyboard.instance.logicalKeysPressed;
            final mod = tracker.isZoomModifierHeld ||
                pressed.contains(LogicalKeyboardKey.altLeft) ||
                pressed.contains(LogicalKeyboardKey.altRight);
            debugPrint('[FloatingImage] scroll dy=${signal.scrollDelta.dy} '
                'tracker=${tracker.isZoomModifierHeld} '
                'HK=${pressed}');
            if (mod) {
              final factor = signal.scrollDelta.dy < 0 ? 1.1 : (1 / 1.1);
              ref
                  .read(floatingImagesProvider.notifier)
                  .updateScale(img.id, img.scale * factor);
            }
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            _scaleAtGestureStart = img.scale;
          },
          onScaleUpdate: (details) {
            final notifier = ref.read(floatingImagesProvider.notifier);
            if (details.pointerCount >= 2) {
              // Two-finger pinch: relative scale to gesture start.
              notifier.updateScale(img.id, _scaleAtGestureStart * details.scale);
            } else {
              // Single pointer (mouse drag / one finger): move the image.
              notifier.updatePosition(
                  img.id, img.position + details.focalPointDelta);
            }
          },
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey.shade900,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    width: renderSize.width,
                    height: renderSize.height,
                    child: const Center(child: CircularProgressIndicator()),
                  )
                else if (_decodedImage != null)
                  // Stack the image with a corner resize handle at bottom-right.
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(8),
                        ),
                        child: SizedBox(
                          width: renderSize.width,
                          height: renderSize.height,
                          child: RawImage(
                            image: _decodedImage,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: _ResizeHandle(
                          onPanUpdate: (deltaY) {
                            final notifier = ref
                                .read(floatingImagesProvider.notifier);
                            // Drag down = grow (positive deltaY → larger scale).
                            final factor = 1 + deltaY * 0.005;
                            notifier.updateScale(
                                img.id, img.scale * factor);
                          },
                        ),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    width: renderSize.width,
                    height: renderSize.height,
                    child: const Center(child: Text('Failed to load')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-right resize handle for the floating image. Dragging vertically
/// zooms the image proportionally.
class _ResizeHandle extends StatefulWidget {
  final void Function(double deltaY) onPanUpdate;

  const _ResizeHandle({required this.onPanUpdate});

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.resizeDownRight,
      child: GestureDetector(
        onPanUpdate: (details) => widget.onPanUpdate(details.delta.dy),
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: _hovering
                ? Colors.tealAccent
                : Colors.white54,
            borderRadius: const BorderRadius.only(
              bottomRight: Radius.circular(8),
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.expand_more,
              size: 12,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
