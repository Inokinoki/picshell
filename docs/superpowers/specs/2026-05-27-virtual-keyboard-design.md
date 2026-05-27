# Virtual Keyboard Bar Design

**Date:** 2026-05-27

## Overview

Add a virtual keyboard bar for mobile devices that provides quick access to special keys commonly used in terminal sessions. The bar appears above the system keyboard when it's visible.

## Design

### Position
- Floating above system keyboard (Option C)
- Only visible when system keyboard is open
- Sits between terminal content and system keyboard

### Layout
```
┌─────────────────────────────────────────────────────────┐
│ Esc │ Tab │ Ctrl │ Alt │ ↑ │ ↓ │ ← │ → │ | │ ~ │ - │
└─────────────────────────────────────────────────────────┘
```

### Behavior
- **Single tap**: Send the key immediately
- **Ctrl/Alt**: Toggle mode - tap to activate, tap again to deactivate, next key press sends with modifier
- **Visual feedback**: Active modifier keys show highlighted state

### Keys
| Key | Action |
|-----|--------|
| Esc | Send escape character |
| Tab | Send tab character |
| Ctrl | Toggle ctrl modifier |
| Alt | Toggle alt modifier |
| ↑ ↓ ← → | Arrow keys |
| \| | Send pipe character |
| ~ | Send tilde character |
| - | Send dash character |

### Implementation
- New widget: `VirtualKeyboardBar`
- Wraps `TerminalView` in `TerminalWidget`
- Listens to `MediaQuery.viewInsets.bottom` to detect keyboard visibility
- Uses `terminal.keyInput()` for special keys
- Uses `terminal.textInput()` for regular characters

### File Changes
- `lib/widgets/virtual_keyboard.dart` - New file
- `lib/widgets/terminal_widget/terminal_widget.dart` - Add keyboard bar
