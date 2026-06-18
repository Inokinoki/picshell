# Picshell

A Flutter-based SSH terminal client with iTerm2 inline image protocol support. Connect to remote hosts, manage sessions in tabs, and view decoded images as floating overlays on top of the terminal.

## Features

- **SSH terminal** -- full terminal emulation via a bundled `xterm` package
- **Multiple sessions** -- tabbed interface for concurrent connections
- **iTerm2 images** -- inline images rendered as draggable, zoomable floating overlays
- **Host management** -- save, edit, and organize connection configurations
- **Authentication** -- password and SSH key authentication
- **Auto-reconnect** -- exponential backoff reconnection on disconnect
- **Settings** -- theme selection (system/light/dark), virtual keyboard bar toggle

## Getting Started

### Prerequisites

- Flutter SDK (^3.12.0)
- macOS, Linux, or Windows (desktop targets)

### Setup

```bash
flutter pub get
flutter run -d macos   # or -d linux / -d windows
```

### Running Tests

```bash
flutter test
```

## Architecture

```
lib/
  main.dart                         Entry point, Hive + ModifierTracker init
  app/
    app.dart                        MaterialApp with GoRouter
    routes.dart                     Route definitions
  models/
    host.dart                       Host model (Hive-persisted)
    session.dart                    Session model
    ssh_key.dart                    SSH key model
    floating_image.dart             Floating image data model
  providers/
    session_provider.dart           SSH session lifecycle + reconnect scheduling
    floating_image_provider.dart    Floating image state (add/remove/scale/drag)
    host_provider.dart              Host list state
    settings_provider.dart          App settings
    key_provider.dart               SSH key state
  screens/
    home/                           Tabbed session view with floating overlay
    hosts/                          Host list and edit screens
    settings/                       App settings
    terminal/                       Terminal wrapper screen
  services/
    ssh_service.dart                SSH connection lifecycle (dartssh2)
    host_store.dart                 Hive-backed host persistence
    agent_forward_service.dart      SSH agent key loading
  widgets/
    floating_image_overlay.dart     Stack-based overlay layer
    floating_image_widget.dart      Draggable/zoomable image widget + ModifierTracker
    terminal_widget/                Terminal rendering widget
    connection_dialog.dart          New connection dialog
    virtual_keyboard.dart           Virtual keyboard bar
```

## Floating Images

When a remote command outputs an [iTerm2 inline image](https://iterm2.com/documentation-images.html), the image is decoded and displayed as a floating overlay.

**Controls:**
- **Drag** -- single-pointer drag moves the image
- **Zoom** -- Option+scroll (Alt+scroll on Linux/Windows)
- **Pinch** -- two-finger pinch to zoom on trackpad
- **Resize handle** -- drag the bottom-right corner to zoom
- **Minimize** -- collapses to a chip in the tab bar
- **Close** -- removes the image

## Tech Stack

| Layer | Choice |
|-------|--------|
| State management | Riverpod |
| Navigation | GoRouter |
| Local storage | Hive |
| Terminal | Bundled `xterm` package |
| SSH | dartssh2 |

## License

[MIT](LICENSE)
