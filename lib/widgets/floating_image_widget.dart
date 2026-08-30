import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart' show Iterm2Dimension, Iterm2Unit;
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

  /// Toggle verbose logging of modifier-key and scroll-zoom events. Off by
  /// default so release builds stay quiet; flip to true (e.g. in `main.dart`
  /// during local debugging) to inspect the zoom pipeline in the console.
  static bool enableDebugLogging = false;

  bool _altHeld = false;
  bool _initialized = false;

  bool get isZoomModifierHeld => _altHeld;

  /// Register once at app startup (idempotent).
  void init() {
    if (_initialized) return;
    _initialized = true;
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
        if (enableDebugLogging) {
          debugPrint('[ModifierTracker] alt DOWN → held=$_altHeld');
        }
      }
    } else if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.altLeft ||
          event.logicalKey == LogicalKeyboardKey.altRight) {
        _altHeld = false;
        if (enableDebugLogging) {
          debugPrint('[ModifierTracker] alt UP → held=$_altHeld');
        }
      }
    }
    return false; // don't consume – let others handle too.
  }
}

/// Computes the initial display size honouring the iTerm2 protocol's
/// `width`/`height` request params when present, falling back to the decoded
/// pixel dimensions, then fitting to 80% of [viewport]. Pure function for
/// testability.
///
/// Dimension semantics (mirrors the iTerm2 spec, parsed by the xterm fork):
/// [Iterm2Unit.cells] counts terminal cells ([cellSize] gives the pixel size
/// of one cell — width for the width axis, height for the height axis),
/// [Iterm2Unit.pixels] is raw pixels, [Iterm2Unit.percent] is a percentage of
/// the viewport. `null` means "no request, use decoded".
Size computeBaseDisplaySize({
  required int decodedWidth,
  required int decodedHeight,
  Iterm2Dimension? requestedWidth,
  Iterm2Dimension? requestedHeight,
  required Size viewport,
  Size cellSize = _defaultCellSize,
}) {
  final w = _resolveDimension(requestedWidth, viewport.width, cellSize.width);
  final h =
      _resolveDimension(requestedHeight, viewport.height, cellSize.height);

  Size size;
  if (w != null && h != null) {
    size = Size(w, h);
  } else if (w != null) {
    final ratio = decodedHeight / decodedWidth;
    size = Size(w, w * ratio);
  } else if (h != null) {
    final ratio = decodedWidth / decodedHeight;
    size = Size(h * ratio, h);
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

/// Approximate pixel size of one terminal cell. The floating-image layer has
/// no handle on the TerminalView's font metrics, so cells resolve with this
/// typical default (12px monospace ≈ 9×18) instead of being misread as raw
/// pixels.
const _defaultCellSize = Size(9, 18);

/// Resolves an iTerm2 dimension request to pixels. `null` → `null` (no
/// request).
double? _resolveDimension(
  Iterm2Dimension? dim,
  double viewportExtent,
  double cellExtent,
) {
  if (dim == null) return null;
  return switch (dim.unit) {
    Iterm2Unit.percent => viewportExtent * dim.value / 100.0,
    Iterm2Unit.pixels => dim.value.toDouble(),
    Iterm2Unit.cells => dim.value * cellExtent,
  };
}

class FloatingImageWidget extends ConsumerStatefulWidget {
  final FloatingImage image;

  const FloatingImageWidget({super.key, required this.image});

  @override
  ConsumerState<FloatingImageWidget> createState() =>
      _FloatingImageWidgetState();
}

class _FloatingImageWidgetState extends ConsumerState<FloatingImageWidget> {
  /// Cap on decoded pixel dimensions. A small PNG can declare e.g.
  /// 20000×20000 and allocate ~1.6 GB when decoded — the provider's raw-byte
  /// budget does not bound decoded pixels, so decode at a bounded resolution.
  static const _maxDecodeDimension = 4096;

  ui.Image? _decodedImage;
  bool _isLoading = true;
  bool _decodeCancelled = false;

  /// Scale captured on gesture start, used to compute absolute scale from the
  /// relative `details.scale` and avoid drift across multiple callbacks.
  double _scaleAtGestureStart = 1.0;

  /// The provider state replaces [widget.image] on every update; gesture
  /// handlers must read the live object or they compute from stale positions.
  FloatingImage? _liveImage(String id) {
    for (final img in ref.read(floatingImagesProvider)) {
      if (img.id == id) return img;
    }
    return null;
  }

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

  @override
  void dispose() {
    _decodeCancelled = true;
    _decodedImage?.dispose();
    _decodedImage = null;
    super.dispose();
  }

  Future<void> _decodeImage() async {
    setState(() {
      _isLoading = true;
    });
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(widget.image.rawBytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      var targetW = descriptor.width;
      var targetH = descriptor.height;
      final largest = targetW > targetH ? targetW : targetH;
      if (largest > _maxDecodeDimension) {
        final factor = _maxDecodeDimension / largest;
        targetW = (targetW * factor).round().clamp(1, _maxDecodeDimension);
        targetH = (targetH * factor).round().clamp(1, _maxDecodeDimension);
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: targetW,
        targetHeight: targetH,
      );
      final frame = await codec.getNextFrame();
      decoded = frame.image;

      if (!mounted || _decodeCancelled) {
        decoded.dispose();
        return;
      }

      // Compute the base size outside setState so a viewport lookup failure
      // (e.g. in headless tests) doesn't corrupt the decoded-image state.
      Size? newSize;
      if (widget.image.size == Size.zero) {
        try {
          final view = View.of(context);
          newSize = computeBaseDisplaySize(
            decodedWidth: decoded.width,
            decodedHeight: decoded.height,
            requestedWidth: widget.image.requestedWidth,
            requestedHeight: widget.image.requestedHeight,
            viewport: Size(
              view.physicalSize.width / view.devicePixelRatio,
              view.physicalSize.height / view.devicePixelRatio,
            ),
          );
        } catch (_) {
          // Viewport unavailable (headless test): fall back to raw pixels.
          newSize =
              Size(decoded.width.toDouble(), decoded.height.toDouble());
        }
      }
      setState(() {
        _decodedImage?.dispose();
        _decodedImage = decoded;
        _isLoading = false;
      });
      if (newSize != null) {
        ref
            .read(floatingImagesProvider.notifier)
            .updateSize(widget.image.id, newSize);
      }
    } catch (_) {
      decoded?.dispose();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = widget.image;
    final baseSize = img.size != Size.zero ? img.size : const Size(200, 200);
    // Actual rendered size = base × user zoom scale.
    final renderSize =
        Size(baseSize.width * img.scale, baseSize.height * img.scale);

    // Clamp the rendered position so an image can never be dragged fully
    // off-screen (it would become unreachable — no gesture or tab reaches it).
    final screenSize = MediaQuery.sizeOf(context);
    final left = img.position.dx.clamp(
      0.0,
      (screenSize.width - 40).clamp(0.0, double.infinity),
    );
    final top = img.position.dy.clamp(
      0.0,
      (screenSize.height - 40).clamp(0.0, double.infinity),
    );

    return Positioned(
      left: left,
      top: top,
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
            if (ModifierTracker.enableDebugLogging) {
              debugPrint('[FloatingImage] scroll dy=${signal.scrollDelta.dy} '
                  'tracker=${tracker.isZoomModifierHeld} '
                  'HK=$pressed');
            }
            if (mod) {
              final factor = signal.scrollDelta.dy < 0 ? 1.1 : (1 / 1.1);
              final current = _liveImage(img.id);
              if (current != null) {
                ref
                    .read(floatingImagesProvider.notifier)
                    .updateScale(img.id, current.scale * factor);
              }
            }
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            _scaleAtGestureStart = _liveImage(img.id)?.scale ?? 1.0;
          },
          onScaleUpdate: (details) {
            final notifier = ref.read(floatingImagesProvider.notifier);
            final current = _liveImage(img.id);
            if (current == null) return;
            if (details.pointerCount >= 2) {
              // Two-finger pinch: relative scale to gesture start.
              notifier.updateScale(
                  img.id, _scaleAtGestureStart * details.scale);
            } else {
              // Single pointer (mouse drag / one finger): move the image.
              // Compute from the live position: multiple pointer callbacks
              // can fire between rebuilds and stale positions drop deltas.
              notifier.updatePosition(
                  img.id, current.position + details.focalPointDelta);
            }
          },
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey.shade900,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: renderSize.width,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.image, size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            img.name,
                            style: TextStyle(
                              color: Colors.grey.shade300,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
                            final current = _liveImage(img.id);
                            if (current == null) return;
                            // Drag down = grow (positive deltaY → larger scale).
                            final factor = 1 + deltaY * 0.005;
                            notifier.updateScale(
                                img.id, current.scale * factor);
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
