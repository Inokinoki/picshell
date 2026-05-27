# Floating Image Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace inline iTerm2 image rendering with draggable floating windows that appear as overlays above the terminal, with minimized images shown as tabs.

**Architecture:** Images are decoded in the xterm Terminal class, then passed via callback to a Riverpod provider. An Overlay system renders floating windows above the terminal. Minimized images appear as chips in the session tab bar.

**Tech Stack:** Flutter, Riverpod, xterm (forked), dart:ui for image decoding

---

## Task 1: Create FloatingImage Model

**Files:**
- Create: `lib/models/floating_image.dart`

- [ ] **Step 1: Create the FloatingImage model class**

```dart
// lib/models/floating_image.dart
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/models/floating_image.dart
git commit -m "feat: add FloatingImage model"
```

---

## Task 2: Create Floating Image Provider

**Files:**
- Create: `lib/providers/floating_image_provider.dart`

- [ ] **Step 1: Create the FloatingImagesNotifier**

```dart
// lib/providers/floating_image_provider.dart
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/providers/floating_image_provider.dart
git commit -m "feat: add floating images provider"
```

---

## Task 3: Create FloatingImageWidget

**Files:**
- Create: `lib/widgets/floating_image_widget.dart`

- [ ] **Step 1: Create the floating image widget with drag, close, minimize**

```dart
// lib/widgets/floating_image_widget.dart
import 'dart:typed_data';
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
            final maxSize = MediaQueryData.fromView(
                    WidgetsBinding.instance.platformDispatcher.views.first)
                .size;
            final maxW = maxSize.width * 0.8;
            final maxH = maxSize.height * 0.8;
            if (size.width > maxW || size.height > maxH) {
              final scale = (maxW / size.width)
                  .clamp(0.0, 1.0)
                  .toDouble()
                  .clamp(0.0, (maxH / size.height).clamp(0.0, 1.0));
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
    final size = img.size != Size.zero
        ? img.size
        : const Size(200, 200);

    return Positioned(
      left: img.position.dx,
      top: img.position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          ref.read(floatingImagesProvider.notifier).updatePosition(
                img.id,
                img.position + details.delta,
              );
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
                      child: Icon(Icons.minimize,
                          size: 14, color: Colors.grey.shade400),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        ref
                            .read(floatingImagesProvider.notifier)
                            .removeImage(img.id);
                      },
                      child: Icon(Icons.close,
                          size: 14, color: Colors.grey.shade400),
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/floating_image_widget.dart
git commit -m "feat: add FloatingImageWidget with drag, close, minimize"
```

---

## Task 4: Create FloatingImageOverlay

**Files:**
- Create: `lib/widgets/floating_image_overlay.dart`

- [ ] **Step 1: Create the overlay manager**

```dart
// lib/widgets/floating_image_overlay.dart
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
        .where((entry) => !currentIds.contains((entry as _ImageOverlayEntry).imageId))
        .toList();

    for (final entry in entriesToRemove) {
      entry.remove();
      _overlayEntries.remove(entry);
    }

    for (final img in images) {
      if (img.minimized) continue;
      final exists = _overlayEntries
          .any((e) => (e as _ImageOverlayEntry).imageId == img.id);
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

  _ImageOverlayEntry({
    required this.imageId,
    required super.builder,
  });
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/floating_image_overlay.dart
git commit -m "feat: add FloatingImageOverlay manager"
```

---

## Task 5: Add onImageDecoded Callback to Terminal

**Files:**
- Modify: `packages/xterm/lib/src/terminal.dart:148-155` (add callback field)
- Modify: `packages/xterm/lib/src/terminal.dart:1011-1047` (modify _decodeIterm2Image)

- [ ] **Step 1: Add the callback field to Terminal class**

In `packages/xterm/lib/src/terminal.dart`, after line 155 (`double cellHeight = 18.0;`), add:

```dart
  /// Callback when an iTerm2 image is decoded.
  /// Receives raw image bytes, filename, and optional width/height from protocol.
  void Function(Uint8List bytes, String name, int? width, int? height)?
      onImageDecoded;
```

- [ ] **Step 2: Modify _decodeIterm2Image to call callback instead of adding to list**

Replace the `_decodeIterm2Image` method (lines 1011-1047) with:

```dart
  Future<void> _decodeIterm2Image(
    String name,
    String base64Combined,
    String? widthStr,
    String? heightStr,
    int cursorRow,
  ) async {
    try {
      final bytes = base64.decode(base64Combined);
      final widthVal = widthStr != null
          ? int.tryParse(widthStr.replaceAll(RegExp(r'[^0-9]'), ''))
          : null;
      final heightVal = heightStr != null
          ? int.tryParse(heightStr.replaceAll(RegExp(r'[^0-9]'), ''))
          : null;

      if (onImageDecoded != null) {
        onImageDecoded!(bytes, name, widthVal, heightVal);
      }
    } catch (_) {
      // Ignore decode errors
    }
  }
```

- [ ] **Step 3: Commit**

```bash
git add packages/xterm/lib/src/terminal.dart
git commit -m "feat: add onImageDecoded callback to Terminal"
```

---

## Task 6: Wire Session Provider to Floating Images

**Files:**
- Modify: `lib/providers/session_provider.dart:36-60` (in openSession)

- [ ] **Step 1: Import floating_image_provider and uuid**

At the top of `lib/providers/session_provider.dart`, add imports:

```dart
import 'dart:typed_data';
import '../models/floating_image.dart';
import 'floating_image_provider.dart';
```

Note: We need a Riverpod `Ref` to access `floatingImagesProvider`. Since `SessionListNotifier` doesn't have one, we'll need to modify the provider to accept a ref.

- [ ] **Step 2: Modify sessionListProvider to use ref**

Replace the provider definition (lines 28-31) with:

```dart
final sessionListProvider =
    StateNotifierProvider<SessionListNotifier, List<SessionState>>((ref) {
      return SessionListNotifier(ref);
    });
```

And update the constructor (line 34):

```dart
class SessionListNotifier extends StateNotifier<List<SessionState>> {
  final Ref _ref;

  SessionListNotifier(this._ref) : super([]);
```

- [ ] **Step 3: Wire onImageDecoded in openSession**

In the `openSession` method, after setting up `terminal.onResize` (around line 47), add:

```dart
    terminal.onImageDecoded = (Uint8List bytes, String imgName, int? w, int? h) {
      final image = FloatingImage(
        id: _uuid.v4(),
        rawBytes: bytes,
        name: imgName,
        requestedWidth: w,
        requestedHeight: h,
      );
      _ref.read(floatingImagesProvider.notifier).addImage(image);
    };
```

- [ ] **Step 4: Commit**

```bash
git add lib/providers/session_provider.dart
git commit -m "feat: wire terminal image decode to floating images provider"
```

---

## Task 7: Add Overlay to HomeScreen

**Files:**
- Modify: `lib/screens/home/home_screen.dart:1-9` (add imports)
- Modify: `lib/screens/home/home_screen.dart:40` (wrap Scaffold)

- [ ] **Step 1: Add import for FloatingImageOverlay**

At the top of `lib/screens/home/home_screen.dart`, add:

```dart
import '../../widgets/floating_image_overlay.dart';
```

- [ ] **Step 2: Wrap Scaffold body with FloatingImageOverlay**

In the `build` method, wrap the `Scaffold` with `FloatingImageOverlay`. Change the return statement to:

```dart
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
            const _NewConnectionIntent(),
      },
      child: Actions(
        actions: {
          _NewConnectionIntent: CallbackAction<_NewConnectionIntent>(
            onInvoke: (_) => _showConnectDialog(context, ref),
          ),
        },
        child: FloatingImageOverlay(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Picshell'),
              actions: [
                // ... existing actions unchanged
              ],
              bottom: sessions.isNotEmpty
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(40),
                      child: _SessionTabBar(
                        // ... existing tab bar params
                      ),
                    )
                  : null,
            ),
            body: sessions.isEmpty
                ? // ... existing empty state
                : _SessionView(sessions: sessions, selectedIndex: clampedIndex),
          ),
        ),
      ),
    );
```

- [ ] **Step 3: Commit**

```bash
git add lib/screens/home/home_screen.dart
git commit -m "feat: add FloatingImageOverlay to HomeScreen"
```

---

## Task 8: Add Minimized Image Tabs to Tab Bar

**Files:**
- Modify: `lib/screens/home/home_screen.dart:146-205` (_SessionTabBar)
- Modify: `lib/screens/home/home_screen.dart:56-85` (AppBar bottom)

- [ ] **Step 1: Update _SessionTabBar to accept and display minimized images**

Replace the `_SessionTabBar` widget with:

```dart
class _SessionTabBar extends StatelessWidget {
  final List<SessionState> sessions;
  final int selectedIndex;
  final void Function(int index) onSelect;
  final void Function(String id) onClose;
  final List<FloatingImage> minimizedImages;
  final void Function(String id) onImageSelect;
  final void Function(String id) onImageClose;

  const _SessionTabBar({
    required this.sessions,
    required this.selectedIndex,
    required this.onSelect,
    required this.onClose,
    this.minimizedImages = const [],
    required this.onImageSelect,
    required this.onImageClose,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Session tabs
          for (int index = 0; index < sessions.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => onSelect(index),
                child: Chip(
                  label: Text(
                    sessions[index].host.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: index == selectedIndex
                          ? Colors.white
                          : Colors.white70,
                      fontWeight: index == selectedIndex
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  deleteIcon: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white70,
                  ),
                  onDeleted: () => onClose(sessions[index].id),
                  backgroundColor: index == selectedIndex
                      ? Colors.teal.shade700
                      : sessions[index].connected
                          ? Colors.teal.shade900
                          : Colors.red.shade900,
                  side: index == selectedIndex
                      ? const BorderSide(color: Colors.tealAccent, width: 2)
                      : null,
                ),
              ),
            ),
          // Minimized image tabs
          if (minimizedImages.isNotEmpty)
            Container(
              width: 1,
              color: Colors.white24,
              margin: const EdgeInsets.symmetric(vertical: 8),
            ),
          for (final img in minimizedImages)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => onImageSelect(img.id),
                child: Chip(
                  avatar: Icon(Icons.image, size: 14, color: Colors.white70),
                  label: Text(
                    img.name,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                  deleteIcon: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white70,
                  ),
                  onDeleted: () => onImageClose(img.id),
                  backgroundColor: Colors.teal.shade900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Update HomeScreen to pass minimized images to tab bar**

Add the import for FloatingImage at the top:

```dart
import '../../models/floating_image.dart';
import '../../providers/floating_image_provider.dart';
```

In the `build` method, add the watch for floating images:

```dart
    final floatingImages = ref.watch(floatingImagesProvider);
    final minimizedImages = floatingImages.where((img) => img.minimized).toList();
```

Update the `_SessionTabBar` instantiation to include the new params:

```dart
              bottom: sessions.isNotEmpty || minimizedImages.isNotEmpty
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(40),
                      child: _SessionTabBar(
                        sessions: sessions,
                        selectedIndex: clampedIndex,
                        onSelect: (index) =>
                            ref
                                    .read(selectedSessionIndexProvider.notifier)
                                    .state =
                                index,
                        onClose: (id) {
                          ref.read(sessionListProvider.notifier).closeSession(id);
                          final current = ref.read(selectedSessionIndexProvider);
                          final newSessions = ref.read(sessionListProvider);
                          if (current >= newSessions.length &&
                              newSessions.isNotEmpty) {
                            ref
                                    .read(selectedSessionIndexProvider.notifier)
                                    .state =
                                newSessions.length - 1;
                          }
                        },
                        minimizedImages: minimizedImages,
                        onImageSelect: (id) {
                          ref
                              .read(floatingImagesProvider.notifier)
                              .toggleMinimize(id);
                        },
                        onImageClose: (id) {
                          ref
                              .read(floatingImagesProvider.notifier)
                              .removeImage(id);
                        },
                      ),
                    )
                  : null,
```

- [ ] **Step 3: Commit**

```bash
git add lib/screens/home/home_screen.dart
git commit -m "feat: add minimized image tabs to session tab bar"
```

---

## Task 9: Remove Old Inline Image Rendering

**Files:**
- Modify: `packages/xterm/lib/src/terminal.dart:148-155` (remove old fields)
- Modify: `packages/xterm/lib/src/ui/painter.dart:281-315` (remove paintImages)
- Modify: `packages/xterm/lib/src/ui/render.dart:424-430` (remove paintImages call)

- [ ] **Step 1: Remove old iterm2Images list and pending chunks from Terminal**

In `packages/xterm/lib/src/terminal.dart`, remove lines 148-155:

```dart
  // REMOVE these lines:
  /// Pending iTerm2 images waiting to be rendered.
  final List<Iterm2Image> iterm2Images = [];

  /// Assembler for chunked base64 iTerm2 image data.
  final Map<String, _PendingChunk> _pendingChunks = {};

  /// Cell height for image rendering (will be updated from render metrics).
  double cellHeight = 18.0;
```

- [ ] **Step 2: Remove _PendingChunk class and _assembleChunk method**

Remove the `_PendingChunk` class (around lines 39-44) and `_assembleChunk` method (around lines 993-1009).

- [ ] **Step 3: Remove _handleIterm2File chunk path**

In `_handleIterm2Image`, simplify to always call `_decodeIterm2Image` directly (no chunk assembly):

```dart
  void _handleIterm2File(String data) {
    if (!data.startsWith('File=')) return;

    final afterPrefix = data.substring('File='.length);
    final colonIndex = afterPrefix.indexOf(':');
    if (colonIndex == -1) return;

    final paramsStr = afterPrefix.substring(0, colonIndex);
    final base64Data = afterPrefix.substring(colonIndex + 1);

    final params = _parseIterm2Params(paramsStr);
    if (params == null) return;

    final name = params['name'] ?? '__default__';
    final size = int.tryParse(params['size'] ?? '0') ?? 0;
    final widthStr = params['width'];
    final heightStr = params['height'];
    final cursorRow = buffer.cursorY;

    _decodeIterm2Image(name, base64Data, widthStr, heightStr, cursorRow);
  }
```

- [ ] **Step 4: Remove paintImages from painter**

In `packages/xterm/lib/src/ui/painter.dart`, remove the entire `paintImages` method (lines 281-315) and the `_resolveDimension` method.

- [ ] **Step 5: Remove paintImages call from render**

In `packages/xterm/lib/src/ui/render.dart`, remove lines 424-430:

```dart
    // REMOVE:
    _painter.paintImages(
      canvas,
      offset,
      _terminal.iterm2Images,
      _painter.cellSize.width,
      _painter.cellSize.height,
      _scrollOffset.toInt(),
    );
```

- [ ] **Step 6: Remove Iterm2Image import from painter**

Remove the import of `Iterm2Image` from `packages/xterm/lib/src/ui/painter.dart`.

- [ ] **Step 7: Commit**

```bash
git add packages/xterm/lib/src/terminal.dart packages/xterm/lib/src/ui/painter.dart packages/xterm/lib/src/ui/render.dart
git commit -m "refactor: remove old inline image rendering from xterm"
```

---

## Task 10: Run and Verify

- [ ] **Step 1: Run flutter analyze**

```bash
flutter analyze
```

Expected: No errors (info warnings acceptable)

- [ ] **Step 2: Run flutter build**

```bash
flutter build macos --debug
```

Expected: Build succeeds

- [ ] **Step 3: Test with SSH connection**

1. Run `flutter run -d macos`
2. Connect to an SSH host
3. Run the 64x64 gradient image command:
```bash
python3 -c "
import base64, struct, zlib
width, height = 64, 64
pixels = b''
for y in range(height):
    for x in range(width):
        r = int(255 * x / width)
        g = int(255 * y / height)
        b = 128
        pixels += struct.pack('BBB', r, g, b)
def make_png(w, h, data):
    def chunk(ctype, cdata):
        c = ctype + cdata
        return struct.pack('>I', len(cdata)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    raw = b''
    for y in range(h):
        raw += b'\x00' + data[y*w*3:(y+1)*w*3]
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
png = make_png(width, height, pixels)
b64 = base64.b64encode(png).decode()
print(f'\033]1337;File=inline=1;size={len(png)}:{b64}\a')
"
```

Expected: Floating window appears at center of terminal

4. Test drag: drag the floating window
5. Test minimize: click minimize button, image appears as tab
6. Test restore: click the image tab, floating window reappears
7. Test close: click close button, image removed

- [ ] **Step 4: Commit final state**

```bash
git add -A
git commit -m "feat: floating image windows with drag, minimize, close"
```
