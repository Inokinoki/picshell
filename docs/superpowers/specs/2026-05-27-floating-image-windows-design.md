# Floating Image Windows Design

## Overview

Replace inline iTerm2 image rendering with draggable floating windows that appear as overlays above the terminal. Minimized images appear as tabs alongside session tabs.

## Goals

1. Images received via iTerm2 protocol display as floating, draggable windows
2. Users can drag, close, and minimize floating windows
3. Minimized images appear as tabs in the session tab bar
4. Clicking a minimized tab restores the floating window

## Architecture

### Data Model

**FloatingImage class** (`lib/models/floating_image.dart`):
```dart
class FloatingImage {
  final String id;          // UUID
  final Uint8List rawBytes; // Original image bytes for re-decoding
  final String name;        // Filename from iTerm2 protocol
  Offset position;          // Current position (draggable)
  Size size;                // Current size (resizable)
  bool minimized;           // Tab state
  int? width;               // Requested width from protocol
  int? height;              // Requested height from protocol
}
```

**Provider** (`lib/providers/floating_image_provider.dart`):
```dart
final floatingImagesProvider = StateNotifierProvider<FloatingImagesNotifier, List<FloatingImage>>
```

Methods:
- `addImage(FloatingImage)` — Add to list, auto-position at center with offset
- `removeImage(String id)` — Remove from list and overlay
- `toggleMinimize(String id)` — Toggle minimized state
- `updatePosition(String id, Offset)` — Update position on drag
- `updateSize(String id, Size)` — Update size on resize

### Widget Components

**FloatingImageWidget** (`lib/widgets/floating_image_widget.dart`):
- `GestureDetector` for drag (`onPanUpdate`)
- Top bar: title + minimize button + close button
- `ClipRRect` with rounded corners
- `Image.memory` or `ui.Image` rendering
- Default size: original image dimensions, max 80% of screen

**FloatingImageOverlay** (`lib/widgets/floating_image_overlay.dart`):
- Manages `OverlayEntry` list based on `floatingImagesProvider`
- Inserts/removes overlay entries as images are added/removed/minimized
- Positioned at image's `position` coordinates

### Terminal Integration

**Changes to Terminal class** (`packages/xterm/lib/src/terminal.dart`):
- Remove `iterm2Images` list and inline rendering code
- Modify `_decodeIterm2Image()` to call a callback instead of adding to list
- Add `onImageDecoded` callback: `void Function(Uint8List bytes, String name, int? width, int? height)?`

**Changes to SessionState** (`lib/providers/session_provider.dart`):
- Wire `terminal.onImageDecoded` to `floatingImagesProvider.addImage()`

### Tab Bar Integration

**Changes to _SessionTabBar** (`lib/screens/home/home_screen.dart`):
- After session tabs, render minimized image tabs
- Each minimized image shows as a chip with thumbnail icon
- Click restores floating window
- Close button removes image

## Flow

```
1. SSH output -> Terminal.write()
2. Parser detects OSC 1337 sequence
3. _handleIterm2File() parses File= params
4. _decodeIterm2Image() decodes base64 -> ui.Image
5. onImageDecoded callback fires with raw bytes + metadata
6. Session provider creates FloatingImage, adds to floatingImagesProvider
7. FloatingImageOverlay creates OverlayEntry
8. FloatingImageWidget renders at center of screen
9. User drags -> updatePosition()
10. User minimizes -> toggleMinimize() -> removed from overlay, shown as tab
11. User clicks tab -> toggleMinimize() -> restored to overlay
```

## Files to Create

- `lib/models/floating_image.dart`
- `lib/providers/floating_image_provider.dart`
- `lib/widgets/floating_image_widget.dart`
- `lib/widgets/floating_image_overlay.dart`

## Files to Modify

- `packages/xterm/lib/src/terminal.dart` — Remove inline image rendering, add callback
- `lib/providers/session_provider.dart` — Wire callback to provider
- `lib/screens/home/home_screen.dart` — Add minimized image tabs to tab bar
- `lib/screens/home/home_screen.dart` — Add Overlay widget

## Constraints

- No dependencies beyond existing ones (flutter_riverpod, uuid already in project)
- Maintain backward compatibility with iTerm2 protocol (File= params)
- Support chunked image data (MultipartFile/FilePart)
- Handle multiple simultaneous images without z-order conflicts
