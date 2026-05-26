# Picshell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cross-platform (iOS + Android) Flutter SSH client that supports iTerm2 inline image protocol, with multi-session management and local host/key storage.

**Architecture:** Fork xterm.dart (TerminalStudio/xterm.dart) for terminal rendering. Modify its `EscapeHandler` to intercept iTerm2 ESC]1337 OSC sequences, and modify `TerminalPainter` to render decoded images on Canvas. SSH via dartssh2 with password/key/agent forwarding. State via Riverpod, persistence via Hive.

**Tech Stack:** Flutter 3.x, dartssh2, xterm (forked), Riverpod, Hive, flutter_riverpod

---

## File Structure

```
picshell/
├── pubspec.yaml
├── packages/
│   └── xterm/                          # Forked xterm.dart
│       ├── pubspec.yaml
│       └── lib/
│           └── src/
│               ├── core/
│               │   └── escape/
│               │       ├── handler.dart    # Add unknownOSC for iTerm2
│               │       └── parser.dart     # OSC parsing (unchanged)
│               ├── terminal.dart           # Add iTerm2 image storage
│               └── ui/
│                   ├── painter.dart        # Add image rendering to Canvas
│                   └── render.dart         # Pass images to painter
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── app.dart                        # MaterialApp + router
│   │   └── routes.dart                     # GoRouter route definitions
│   ├── models/
│   │   ├── host.dart                       # Host data model (Hive type)
│   │   ├── ssh_key.dart                    # SSH key data model (Hive type)
│   │   └── session.dart                    # Session data model
│   ├── services/
│   │   ├── ssh_service.dart                # dartssh2 wrapper
│   │   ├── agent_forward_service.dart      # SSH agent forwarding
│   │   └── host_store.dart                 # Hive CRUD for hosts/keys
│   ├── providers/
│   │   ├── session_provider.dart           # Riverpod: active sessions
│   │   ├── host_provider.dart              # Riverpod: host list
│   │   └── key_provider.dart               # Riverpod: SSH keys
│   ├── screens/
│   │   ├── home/
│   │   │   └── home_screen.dart            # Tab bar + terminal area
│   │   ├── terminal/
│   │   │   └── terminal_screen.dart        # Single terminal session
│   │   └── hosts/
│   │       ├── host_list_screen.dart       # Host list view
│   │       └── host_edit_screen.dart       # Add/edit host
│   ├── widgets/
│   │   └── connection_dialog.dart          # SSH connect dialog
│   └── utils/
│       └── base64_chunk_assembler.dart     # Chunked base64 decoder
├── test/
│   ├── services/
│   │   ├── iterm2_parser_test.dart
│   │   └── ssh_service_test.dart
│   └── widgets/
│       └── terminal_widget_test.dart
└── docs/
    └── specs/
        └── 2026-05-26-ssh-client-design.md
```

---

## Task 1: Project Setup & Dependencies

**Files:**
- Create: `pubspec.yaml`
- Create: `lib/main.dart`

- [ ] **Step 1: Create Flutter project**

```bash
cd ~/Builds/picshell
flutter create --org com.picshell --project-name picshell .
```

- [ ] **Step 2: Clone xterm.dart as local package**

```bash
cd ~/Builds/picshell
git clone https://github.com/TerminalStudio/xterm.dart.git packages/xterm
cd packages/xterm && git checkout v4.0.0
```

- [ ] **Step 3: Add dependencies to `pubspec.yaml`**

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.4.0
  riverpod_annotation: ^2.3.0
  dartssh2: ^2.8.0
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  go_router: ^13.0.0
  uuid: ^4.3.0
  pointycastle: ^3.9.0
  encrypt: ^5.0.3
  file_picker: ^6.1.0
  xterm:
    path: packages/xterm

dev_dependencies:
  flutter_test:
    sdk: flutter
  hive_generator: ^2.0.1
  build_runner: ^2.4.8
  riverpod_generator: ^2.4.0
  mockito: ^5.4.4
```

- [ ] **Step 4: Initialize Hive in `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const ProviderScope(child: PicshellApp()));
}
```

- [ ] **Step 5: Verify project builds**

```bash
cd ~/Builds/picshell && flutter build apk --debug 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
cd ~/Builds/picshell && git add -A && git commit -m "feat: scaffold Flutter project with xterm.dart fork and dependencies"
```

---

## Task 2: Data Models (Hive)

**Files:**
- Create: `lib/models/host.dart`
- Create: `lib/models/ssh_key.dart`
- Create: `lib/models/session.dart`

- [ ] **Step 1: Create `lib/models/host.dart`**

```dart
import 'package:hive/hive.dart';

part 'host.g.dart';

@HiveType(typeId: 0)
class Host extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String hostname;

  @HiveField(3)
  int port;

  @HiveField(4)
  String username;

  @HiveField(5)
  AuthType authType;

  @HiveField(6)
  String? keyId;

  @HiveField(7)
  String? password;

  @HiveField(8)
  String? groupId;

  Host({
    required this.id,
    required this.name,
    required this.hostname,
    this.port = 22,
    required this.username,
    this.authType = AuthType.password,
    this.keyId,
    this.password,
    this.groupId,
  });
}

@HiveType(typeId: 1)
enum AuthType {
  @HiveField(0)
  password,
  @HiveField(1)
  key,
}
```

- [ ] **Step 2: Create `lib/models/ssh_key.dart`**

```dart
import 'package:hive/hive.dart';

part 'ssh_key.g.dart';

@HiveType(typeId: 2)
class SshKey extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String privateKeyPem;

  @HiveField(3)
  String publicKey;

  SshKey({
    required this.id,
    required this.name,
    required this.privateKeyPem,
    required this.publicKey,
  });
}
```

- [ ] **Step 3: Create `lib/models/session.dart`**

```dart
import 'package:hive/hive.dart';

part 'session.g.dart';

@HiveType(typeId: 3)
class Session extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String hostId;

  @HiveField(2)
  DateTime lastActive;

  Session({
    required this.id,
    required this.hostId,
    required this.lastActive,
  });
}
```

- [ ] **Step 4: Run build_runner to generate adapters**

```bash
cd ~/Builds/picshell && dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 5: Commit**

```bash
cd ~/Builds/picshell && git add -A && git commit -m "feat: add Hive data models (Host, SshKey, Session)"
```

---

## Task 3: Host Store (Hive CRUD)

**Files:**
- Create: `lib/services/host_store.dart`

- [ ] **Step 1: Create `lib/services/host_store.dart`**

```dart
import 'package:hive/hive.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../models/session.dart';

class HostStore {
  static const _hostsBox = 'hosts';
  static const _keysBox = 'ssh_keys';
  static const _sessionsBox = 'sessions';

  late Box<Host> _hosts;
  late Box<SshKey> _keys;
  late Box<Session> _sessions;

  Future<void> init() async {
    _hosts = await Hive.openBox<Host>(_hostsBox);
    _keys = await Hive.openBox<SshKey>(_keysBox);
    _sessions = await Hive.openBox<Session>(_sessionsBox);
  }

  // Host CRUD
  List<Host> getHosts() => _hosts.values.toList();

  Future<void> addHost(Host host) async {
    await _hosts.put(host.id, host);
  }

  Future<void> updateHost(Host host) async {
    await _hosts.put(host.id, host);
  }

  Future<void> deleteHost(String id) async {
    await _hosts.delete(id);
  }

  Host? getHost(String id) => _hosts.get(id);

  // SSH Key CRUD
  List<SshKey> getKeys() => _keys.values.toList();

  Future<void> addKey(SshKey key) async {
    await _keys.put(key.id, key);
  }

  Future<void> deleteKey(String id) async {
    await _keys.delete(id);
  }

  SshKey? getKey(String id) => _keys.get(id);

  // Session CRUD
  List<Session> getSessions() => _sessions.values.toList();

  Future<void> saveSession(Session session) async {
    await _sessions.put(session.id, session);
  }

  Future<void> deleteSession(String id) async {
    await _sessions.delete(id);
  }
}
```

- [ ] **Step 2: Write test `test/services/host_store_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/services/host_store.dart';
import 'dart:io';

void main() {
  late HostStore store;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('picshell_test_');
    Hive.init(tempDir.path);
    Hive.registerAdapter(HostAdapter());
    Hive.registerAdapter(AuthTypeAdapter());
    store = HostStore();
    await store.init();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  test('add and retrieve host', () async {
    final host = Host(
      id: '1',
      name: 'Test',
      hostname: '192.168.1.1',
      username: 'root',
    );
    await store.addHost(host);
    expect(store.getHosts().length, 1);
    expect(store.getHost('1')?.name, 'Test');
  });

  test('delete host', () async {
    final host = Host(id: '1', name: 'Test', hostname: '1.2.3.4', username: 'u');
    await store.addHost(host);
    await store.deleteHost('1');
    expect(store.getHosts().length, 0);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd ~/Builds/picshell && flutter test test/services/host_store_test.dart
```

- [ ] **Step 4: Run test to verify it passes (after Step 1)**

```bash
cd ~/Builds/picshell && flutter test test/services/host_store_test.dart
```

- [ ] **Step 5: Commit**

```bash
cd ~/Builds/picshell && git add -A && git commit -m "feat: add HostStore with Hive CRUD operations"
```

---

## Task 4: iTerm2 Protocol Parser

> **SKIPPED** — iTerm2 protocol parsing is now integrated directly into the xterm.dart fork in Task 6 (`Terminal.unknownOSC` handles ESC]1337 parsing, chunk assembly, and image decoding). No standalone parser file is needed.

- [ ] **Step 1: Skip this task — proceed to Task 5**

---

## Task 5: SSH Service (dartssh2 Wrapper)

**Files:**
- Create: `lib/services/ssh_service.dart`
- Create: `test/services/ssh_service_test.dart`

- [ ] **Step 1: Create `lib/services/ssh_service.dart`**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';

enum SshAuthMethod { password, key, agent }

class SshConnectionConfig {
  final String host;
  final int port;
  final String username;
  final SshAuthMethod authMethod;
  final String? password;
  final String? privateKeyPem;
  final String? passphrase;

  SshConnectionConfig({
    required this.host,
    this.port = 22,
    required this.username,
    required this.authMethod,
    this.password,
    this.privateKeyPem,
    this.passphrase,
  });
}

class SshService {
  SSHClient? _client;
  SSHSession? _session;
  final StreamController<String> _outputController = StreamController.broadcast();
  final StreamController<bool> _connectionController = StreamController.broadcast();

  Stream<String> get output => _outputController.stream;
  Stream<bool> get connectionState => _connectionController.stream;
  bool get isConnected => _client != null && _session != null;

  Future<void> connect(SshConnectionConfig config) async {
    try {
      _connectionController.add(false);

      final socket = await SSHSocket.connect(config.host, config.port);

      SSHClient client;
      switch (config.authMethod) {
        case SshAuthMethod.password:
          client = SSHClient(
            socket,
            username: config.username,
            onPasswordRequest: () => config.password ?? '',
          );
          break;
        case SshAuthMethod.key:
          final keyPair = SSHKeyPair.fromPem(config.privateKeyPem!, config.passphrase);
          client = SSHClient(
            socket,
            username: config.username,
            identities: [keyPair],
          );
          break;
        case SshAuthMethod.agent:
          client = SSHClient(
            socket,
            username: config.username,
            // Agent forwarding is handled after session is open
          );
          break;
      }

      _client = client;
      _session = await client.shell(
        pty: SSHTerminalPty(
          width: 80,
          height: 24,
          term: 'xterm-256color',
        ),
      );

      _session!.stdout
          .transform(utf8.decoder)
          .listen((data) => _outputController.add(data));

      _session!.stderr
          .transform(utf8.decoder)
          .listen((data) => _outputController.add(data));

      _connectionController.add(true);
    } catch (e) {
      _connectionController.addError(e);
      rethrow;
    }
  }

  void writeToTerminal(String data) {
    _session?.write(utf8.encode(data));
  }

  void resizeTerminal(int width, int height) {
    _session?.resizeTerminal(width, height);
  }

  Future<void> disconnect() async {
    await _session?.close();
    await _client?.close();
    _client = null;
    _session = null;
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _outputController.close();
    _connectionController.close();
  }
}
```

- [ ] **Step 2: Write test `test/services/ssh_service_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/services/ssh_service.dart';

void main() {
  group('SshService', () {
    test('connection config can be created', () {
      final config = SshConnectionConfig(
        host: '192.168.1.1',
        username: 'root',
        authMethod: SshAuthMethod.password,
        password: 'test',
      );
      expect(config.host, '192.168.1.1');
      expect(config.port, 22);
      expect(config.authMethod, SshAuthMethod.password);
    });

    test('SshService initial state', () {
      final service = SshService();
      expect(service.isConnected, false);
    });
  });
}
```

- [ ] **Step 3: Run SSH service tests**

```bash
cd ~/Builds/picshell && flutter test test/services/ssh_service_test.dart
```

- [ ] **Step 4: Commit**

```bash
cd ~/Builds/picshell && git add -A && git commit -m "feat: add SSH service wrapper around dartssh2"
```

---

## Task 6: Fork xterm.dart — iTerm2 Image Protocol Support

**Files:**
- Modify: `packages/xterm/lib/src/core/escape/handler.dart` — add `unknownOSC` callback
- Modify: `packages/xterm/lib/src/core/escape/parser.dart` — forward iTerm2 OSC to handler
- Modify: `packages/xterm/lib/src/terminal.dart` — store pending images, implement OSC callback
- Modify: `packages/xterm/lib/src/ui/painter.dart` — render images on Canvas
- Modify: `packages/xterm/lib/src/ui/render.dart` — pass image data to painter

- [ ] **Step 1: Add iTerm2 image model to `packages/xterm/lib/src/terminal.dart`**

Add at the top of the file (after imports):

```dart
import 'dart:ui' as ui;
import 'dart:convert';

class Iterm2Image {
  final ui.Image image;
  final int cursorRow;
  final int? width;
  final int? height;

  Iterm2Image({
    required this.image,
    required this.cursorRow,
    this.width,
    this.height,
  });
}
```

- [ ] **Step 2: Modify `EscapeHandler` to support unknown OSC**

Open `packages/xterm/lib/src/core/escape/handler.dart` and add this method to the `EscapeHandler` mixin:

```dart
/// Called when an OSC sequence is not recognized by the parser.
/// [code] is the OSC command number (e.g., 1337 for iTerm2).
/// [data] is the raw payload string after "code;".
void unknownOSC(int code, String data) {}
```

- [ ] **Step 3: Modify `EscapeParser` to call `unknownOSC` for unrecognized OSC**

Open `packages/xterm/lib/src/core/escape/parser.dart`. Find the `_escHandleOSC()` method. In the switch/case for recognized OSC codes (0, 1, 2), add a `default:` branch that calls:

```dart
default:
  handler.unknownOSC(code, payload);
  break;
```

Where `code` is the parsed integer before the first `;`, and `payload` is everything after `code;`.

- [ ] **Step 4: Implement `unknownOSC` in `Terminal` to handle iTerm2 protocol**

Open `packages/xterm/lib/src/terminal.dart`. Add these fields and methods to the `Terminal` class:

```dart
/// Pending iTerm2 images waiting to be rendered.
final List<Iterm2Image> iterm2Images = [];

/// Assembler for chunked base64 iTerm2 image data.
final Map<String, _PendingChunk> _pendingChunks = {};

@override
void unknownOSC(int code, String data) {
  if (code == 1337) {
    _handleIterm2File(data);
  }
}

void _handleIterm2File(String data) {
  // Format: File=<params>;<base64data>
  if (!data.startsWith('File=')) return;

  final afterPrefix = data.substring('File='.length);
  final semiIndex = afterPrefix.indexOf(';');
  if (semiIndex == -1) return;

  final paramsStr = afterPrefix.substring(0, semiIndex);
  final base64Data = afterPrefix.substring(semiIndex + 1);

  final params = _parseIterm2Params(paramsStr);
  if (params == null) return;

  final name = params['name'] ?? '__default__';
  final size = int.tryParse(params['size'] ?? '0') ?? 0;
  if (size == 0) return;

  final width = _parseDimension(params['width']);
  final height = _parseDimension(params['height']);

  _assembleChunk(name, base64Data, size, width, height);
}

Map<String, String>? _parseIterm2Params(String s) {
  final result = <String, String>{};
  for (final part in s.split(',')) {
    final eq = part.indexOf('=');
    if (eq == -1) continue;
    result[part.substring(0, eq)] = part.substring(eq + 1);
  }
  return result.isEmpty ? null : result;
}

int? _parseDimension(String? s) {
  if (s == null || s == 'auto' || s.endsWith('%')) return null;
  return int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), ''));
}

void _assembleChunk(
  String name,
  String base64Chunk,
  int totalSize,
  int? width,
  int? height,
) {
  final entry = _pendingChunks.putIfAbsent(
    name,
    () => _PendingChunk(totalSize: totalSize),
  );
  entry.buffer.add(base64Chunk);

  final combined = entry.buffer.join();
  // Base64 decoded size = combined.length * 3 / 4 (approx)
  if (combined.length * 3 ~/ 4 >= totalSize) {
    _pendingChunks.remove(name);
    _decodeIterm2Image(name, combined, width, height);
  }
}

Future<void> _decodeIterm2Image(
  String name,
  String base64Combined,
  int? width,
  int? height,
) async {
  try {
    final bytes = base64.decode(base64Combined);
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: width,
      targetHeight: height,
    );
    final frame = await codec.getNextFrame();
    iterm2Images.add(Iterm2Image(
      image: frame.image,
      cursorRow: buffer.cursorY,
      width: width,
      height: height,
    ));
    // Reserve vertical space: move cursor down by image height in terminal rows
    final imgHeight = height ?? frame.image.height;
    final rows = (imgHeight / cellHeight).ceil();
    for (int i = 0; i < rows; i++) {
      buffer.newLine();
    }
    refreshView();
  } catch (_) {
    // Ignore decode errors (malformed base64, unsupported format)
  }
}

double get cellHeight => 18.0; // Will be overridden by render metrics
```

- [ ] **Step 5: Modify `TerminalPainter` to render images**

Open `packages/xterm/lib/src/ui/painter.dart`. Add a method to paint images after text:

```dart
import 'dart:ui' as ui;
import '../terminal.dart' show Iterm2Image;

/// Paint iTerm2 inline images onto the terminal canvas.
void paintImages(
  Canvas canvas,
  List<Iterm2Image> images,
  double cellWidth,
  double cellHeight,
  int scrollOffset,
) {
  for (final entry in images) {
    final visibleRow = entry.cursorRow - scrollOffset;
    // Skip images far outside viewport
    if (visibleRow < -50) continue;

    final y = visibleRow * cellHeight;
    final imgW = entry.width?.toDouble() ?? entry.image.width.toDouble();
    final imgH = entry.height?.toDouble() ?? entry.image.height.toDouble();

    final src = Rect.fromLTWH(
      0, 0,
      entry.image.width.toDouble(),
      entry.image.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, y, imgW, imgH);

    canvas.drawImageRect(entry.image, src, dst, Paint());
  }
}
```

- [ ] **Step 6: Wire image painting into `RenderTerminal.paint()`**

Open `packages/xterm/lib/src/ui/render.dart`. In the `paint()` method, after the text painting loop and before painting cursor/composing, add:

```dart
_painter.paintImages(
  canvas,
  terminal.iterm2Images,
  _cellWidth,
  _cellHeight,
  terminal.scrollOffsetFromBottom,
);
```

- [ ] **Step 7: Wire terminal output through SSH to `terminal.write()`**

In `lib/screens/terminal/terminal_screen.dart` or wherever SSH output is consumed, ensure the flow is:

```dart
sshService.output.listen((data) {
  terminal.write(data);
});
```

The `terminal.write()` call goes through `EscapeParser`, which will call `unknownOSC(1337, ...)` for iTerm2 sequences, triggering the image pipeline.

- [ ] **Step 8: Verify fork compiles**

```bash
cd ~/Builds/picshell && flutter analyze packages/xterm/lib/
```

- [ ] **Step 9: Commit fork changes**

```bash
cd ~/Builds/picshell && git add -A && git commit -m "feat: fork xterm.dart with iTerm2 inline image protocol support"
```

---

## Task 7: Riverpod Providers

**Files:**
- Create: `lib/providers/session_provider.dart`
- Create: `lib/providers/host_provider.dart`
- Create: `lib/providers/key_provider.dart`

- [ ] **Step 1: Create `lib/providers/host_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/host.dart';
import '../services/host_store.dart';

final hostStoreProvider = Provider<HostStore>((ref) {
  throw UnimplementedError('Initialize HostStore in main()');
});

final hostListProvider = StateNotifierProvider<HostListNotifier, List<Host>>((ref) {
  final store = ref.watch(hostStoreProvider);
  return HostListNotifier(store);
});

class HostListNotifier extends StateNotifier<List<Host>> {
  final HostStore _store;

  HostListNotifier(this._store) : super(_store.getHosts());

  void refresh() => state = _store.getHosts();

  Future<void> add(Host host) async {
    await _store.addHost(host);
    refresh();
  }

  Future<void> update(Host host) async {
    await _store.updateHost(host);
    refresh();
  }

  Future<void> delete(String id) async {
    await _store.deleteHost(id);
    refresh();
  }
}
```

- [ ] **Step 2: Create `lib/providers/key_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ssh_key.dart';
import '../services/host_store.dart';

final keyListProvider = StateNotifierProvider<KeyListNotifier, List<SshKey>>((ref) {
  final store = ref.watch(hostStoreProvider);
  return KeyListNotifier(store);
});

class KeyListNotifier extends StateNotifier<List<SshKey>> {
  final HostStore _store;

  KeyListNotifier(this._store) : super(_store.getKeys());

  void refresh() => state = _store.getKeys();

  Future<void> add(SshKey key) async {
    await _store.addKey(key);
    refresh();
  }

  Future<void> delete(String id) async {
    await _store.deleteKey(id);
    refresh();
  }
}
```

- [ ] **Step 3: Create `lib/providers/session_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/host.dart';
import '../services/ssh_service.dart';

class SessionState {
  final String id;
  final Host host;
  final SshService sshService;
  final bool connected;

  SessionState({
    required this.id,
    required this.host,
    required this.sshService,
    this.connected = false,
  });
}

final sessionListProvider =
    StateNotifierProvider<SessionListNotifier, List<SessionState>>((ref) {
  return SessionListNotifier();
});

class SessionListNotifier extends StateNotifier<List<SessionState>> {
  SessionListNotifier() : super([]);

  Future<void> openSession(Host host, SshConnectionConfig config) async {
    final service = SshService();
    final session = SessionState(
      id: host.id,
      host: host,
      sshService: service,
    );
    state = [...state, session];

    try {
      await service.connect(config);
      state = [
        for (final s in state)
          if (s.id == session.id) SessionState(
            id: s.id, host: s.host, sshService: s.sshService, connected: true,
          ) else s
      ];
    } catch (e) {
      closeSession(session.id);
      rethrow;
    }
  }

  void closeSession(String id) {
    final session = state.firstWhere((s) => s.id == id, orElse: () => throw StateError('Not found'));
    session.sshService.dispose();
    state = state.where((s) => s.id != id).toList();
  }
}
```

- [ ] **Step 4: Run provider tests**

```bash
cd ~/Builds/picshell && flutter analyze lib/providers/
```

- [ ] **Step 5: Commit**

```bash
cd ~/Builds/picshell && git add -A && git commit -m "feat: add Riverpod providers for hosts, keys, sessions"
```

---

## Task 8: App Shell & Routing

**Files:**
- Create: `lib/app/app.dart`
- Create: `lib/app/routes.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Create `lib/app/routes.dart`**

```dart
import 'package:go_router/go_router.dart';
import '../screens/home/home_screen.dart';
import '../screens/hosts/host_list_screen.dart';
import '../screens/hosts/host_edit_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/hosts',
      builder: (context, state) => const HostListScreen(),
    ),
    GoRoute(
      path: '/hosts/edit',
      builder: (context, state) => const HostEditScreen(),
    ),
    GoRoute(
      path: '/hosts/edit/:id',
      builder: (context, state) => HostEditScreen(
        hostId: state.pathParameters['id'],
      ),
    ),
  ],
);
```

- [ ] **Step 2: Create `lib/app/app.dart`**

```dart
import 'package:flutter/material.dart';
import 'routes.dart';

class PicshellApp extends StatelessWidget {
  const PicshellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Picshell',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        colorScheme: ColorScheme.dark(
          primary: Colors.tealAccent,
          secondary: Colors.tealAccent.shade700,
        ),
      ),
      routerConfig: router,
    );
  }
}
```

- [ ] **Step 3: Update `lib/main.dart` to initialize HostStore**

```dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picshell/app/app.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/providers/host_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(HostAdapter());
  Hive.registerAdapter(AuthTypeAdapter());
  Hive.registerAdapter(SshKeyAdapter());
  Hive.registerAdapter(SessionAdapter());

  final hostStore = HostStore();
  await hostStore.init();

  runApp(
    ProviderScope(
      overrides: [
        hostStoreProvider.overrideWithValue(hostStore),
      ],
      child: const PicshellApp(),
    ),
  );
}
```

- [ ] **Step 4: Verify build**

```bash
cd ~/Builds/picshell && flutter analyze
```

- [ ] **Step 5: Commit**

```bash
cd ~/Builds/picshell && git add -A && git commit -m "feat: add app shell, routing, and Hive initialization"
```

---

## Task 9: Home Screen (Tab Bar + Terminal Area)

**Files:**
- Create: `lib/screens/home/home_screen.dart`
- Create: `lib/widgets/connection_dialog.dart`

- [ ] **Step 1: Create `lib/widgets/connection_dialog.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/host.dart';
import '../providers/host_provider.dart';
import '../services/ssh_service.dart';

class ConnectionDialog extends ConsumerStatefulWidget {
  final void Function(Host host, SshConnectionConfig config) onConnect;

  const ConnectionDialog({super.key, required this.onConnect});

  @override
  ConsumerState<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends ConsumerState<ConnectionDialog> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  Host? _selectedSavedHost;

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(hostListProvider);

    return AlertDialog(
      title: const Text('New Connection'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hosts.isNotEmpty) ...[
              DropdownButton<Host>(
                isExpanded: true,
                hint: const Text('Select saved host'),
                value: _selectedSavedHost,
                items: hosts.map((h) => DropdownMenuItem(
                  value: h,
                  child: Text('${h.name} (${h.hostname})'),
                )).toList(),
                onChanged: (host) {
                  setState(() {
                    _selectedSavedHost = host;
                    if (host != null) {
                      _hostController.text = host.hostname;
                      _portController.text = host.port.toString();
                      _userController.text = host.username;
                    }
                  });
                },
              ),
              const Divider(),
            ],
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(labelText: 'Host'),
            ),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _userController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final host = _selectedSavedHost ?? Host(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: _hostController.text,
              hostname: _hostController.text,
              port: int.tryParse(_portController.text) ?? 22,
              username: _userController.text,
            );

            final config = SshConnectionConfig(
              host: host.hostname,
              port: host.port,
              username: host.username,
              authMethod: SshAuthMethod.password,
              password: _passwordController.text,
            );

            widget.onConnect(host, config);
            Navigator.pop(context);
          },
          child: const Text('Connect'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 2: Create `lib/screens/home/home_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/host.dart';
import '../../providers/session_provider.dart';
import '../../services/ssh_service.dart';
import '../../widgets/connection_dialog.dart';
import '../terminal/terminal_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Picshell'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns),
            onPressed: () => context.push('/hosts'),
            tooltip: 'Manage Hosts',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showConnectDialog(context, ref),
            tooltip: 'New Connection',
          ),
        ],
        bottom: sessions.isNotEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: _SessionTabBar(
                  sessions: sessions,
                  onClose: (id) => ref.read(sessionListProvider.notifier).closeSession(id),
                ),
              )
            : null,
      ),
      body: sessions.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.terminal, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No active sessions', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showConnectDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('New Connection'),
                  ),
                ],
              ),
            )
          : _SessionView(sessions: sessions),
    );
  }

  void _showConnectDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => ConnectionDialog(
        onConnect: (Host host, SshConnectionConfig config) async {
          try {
            await ref.read(sessionListProvider.notifier).openSession(host, config);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Connection failed: $e')),
              );
            }
          }
        },
      ),
    );
  }
}

class _SessionTabBar extends StatelessWidget {
  final List<SessionState> sessions;
  final void Function(String id) onClose;

  const _SessionTabBar({required this.sessions, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Chip(
              label: Text(
                session.host.name,
                style: const TextStyle(fontSize: 12),
              ),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () => onClose(session.id),
              backgroundColor: session.connected
                  ? Colors.teal.shade900
                  : Colors.red.shade900,
            ),
          );
        },
      ),
    );
  }
}

class _SessionView extends StatelessWidget {
  final List<SessionState> sessions;

  const _SessionView({required this.sessions});

  @override
  Widget build(BuildContext context) {
    // Simple single-session view for now; can extend to tab switching later
    final session = sessions.last;
    return TerminalScreen(sshService: session.sshService);
  }
}
```

- [ ] **Step 3: Create `lib/screens/terminal/terminal_screen.dart`**

```dart
import 'package:flutter/material.dart';
import '../../services/ssh_service.dart';
import '../../widgets/terminal_widget/terminal_widget.dart';

class TerminalScreen extends StatelessWidget {
  final SshService sshService;

  const TerminalScreen({super.key, required this.sshService});

  @override
  Widget build(BuildContext context) {
    return TerminalWidget(sshService: sshService);
  }
}
```

- [ ] **Step 4: Verify build**

```bash
cd ~/Builds/picshell && flutter analyze
```

- [ ] **Step 5: Commit**

```bash
cd ~/Builds/picshell && git add -A && git commit -m "feat: add home screen with session tabs and connection dialog"
```

---

## Task 10: Host Management Screens

**Files:**
- Create: `lib/screens/hosts/host_list_screen.dart`
- Create: `lib/screens/hosts/host_edit_screen.dart`

- [ ] **Step 1: Create `lib/screens/hosts/host_list_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/host_provider.dart';

class HostListScreen extends ConsumerWidget {
  const HostListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Hosts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/hosts/edit'),
          ),
        ],
      ),
      body: hosts.isEmpty
          ? const Center(child: Text('No saved hosts'))
          : ListView.builder(
              itemCount: hosts.length,
              itemBuilder: (context, index) {
                final host = hosts[index];
                return ListTile(
                  title: Text(host.name),
                  subtitle: Text('${host.username}@${host.hostname}:${host.port}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => ref.read(hostListProvider.notifier).delete(host.id),
                  ),
                  onTap: () => context.push('/hosts/edit/${host.id}'),
                );
              },
            ),
    );
  }
}
```

- [ ] **Step 2: Create `lib/screens/hosts/host_edit_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../models/host.dart';
import '../../providers/host_provider.dart';

class HostEditScreen extends ConsumerStatefulWidget {
  final String? hostId;

  const HostEditScreen({super.key, this.hostId});

  @override
  ConsumerState<HostEditScreen> createState() => _HostEditScreenState();
}

class _HostEditScreenState extends ConsumerState<HostEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _userController = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    if (widget.hostId != null) {
      _isEditing = true;
      final hosts = ref.read(hostListProvider);
      final host = hosts.firstWhere((h) => h.id == widget.hostId);
      _nameController.text = host.name;
      _hostController.text = host.hostname;
      _portController.text = host.port.toString();
      _userController.text = host.username;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Host' : 'Add Host'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Display Name'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(labelText: 'Hostname / IP'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: _userController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final notifier = ref.read(hostListProvider.notifier);

    if (_isEditing) {
      final hosts = ref.read(hostListProvider);
      final host = hosts.firstWhere((h) => h.id == widget.hostId);
      host.name = _nameController.text;
      host.hostname = _hostController.text;
      host.port = int.tryParse(_portController.text) ?? 22;
      host.username = _userController.text;
      notifier.update(host);
    } else {
      final host = Host(
        id: const Uuid().v4(),
        name: _nameController.text,
        hostname: _hostController.text,
        port: int.tryParse(_portController.text) ?? 22,
        username: _userController.text,
      );
      notifier.add(host);
    }

    Navigator.pop(context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 3: Verify build**

```bash
cd ~/Builds/picshell && flutter analyze
```

- [ ] **Step 4: Commit**

```bash
cd ~/Builds/picshell && git add -A && git commit -m "feat: add host list and edit screens"
```

---

## Task 11: SSH Key Management (Import & Use)

**Files:**
- Modify: `lib/screens/hosts/host_edit_screen.dart` — add key selection
- Modify: `lib/services/ssh_service.dart` — ensure key auth works
- Modify: `lib/widgets/connection_dialog.dart` — support key auth

- [ ] **Step 1: Add key import to host edit screen**

Add to `host_edit_screen.dart` after the username field:

```dart
// Inside the Form column, after username TextFormField:
DropdownButtonFormField<String>(
  decoration: const InputDecoration(labelText: 'Auth Method'),
  value: _authType,
  items: const [
    DropdownMenuItem(value: 'password', child: Text('Password')),
    DropdownMenuItem(value: 'key', child: Text('SSH Key')),
  ],
  onChanged: (v) => setState(() => _authType = v ?? 'password'),
),
if (_authType == 'key')
  ElevatedButton.icon(
    onPressed: _importKey,
    icon: const Icon(Icons.key),
    label: const Text('Import Private Key'),
  ),
```

Add state variables:

```dart
String _authType = 'password';
String? _selectedKeyId;

Future<void> _importKey() async {
  // Use file_picker to select key file
  // Store via keyListProvider
}
```

- [ ] **Step 2: Update connection dialog to support key auth**

Update `ConnectionDialog` to check host authType and pass appropriate config:

```dart
// In the connect onPressed:
final config = SshConnectionConfig(
  host: host.hostname,
  port: host.port,
  username: host.username,
  authMethod: host.authType == AuthType.key
      ? SshAuthMethod.key
      : SshAuthMethod.password,
  password: host.authType == AuthType.password ? _passwordController.text : null,
  privateKeyPem: host.authType == AuthType.key ? _getKeyPem(host.keyId) : null,
);
```

- [ ] **Step 3: Verify build**

```bash
cd ~/Builds/picshell && flutter analyze
```

- [ ] **Step 4: Commit**

```bash
cd ~/Builds/picshell && git add -A && git commit -m "feat: add SSH key import and key-based auth support"
```

---

## Task 12: Agent Forwarding

**Files:**
- Create: `lib/services/agent_forward_service.dart`
- Modify: `lib/services/ssh_service.dart`

- [ ] **Step 1: Create `lib/services/agent_forward_service.dart`**

```dart
import 'package:dartssh2/dartssh2.dart';

class AgentForwardService {
  /// Request agent forwarding on an active SSH session.
  /// This allows the remote host to use local SSH keys for further connections.
  static Future<void> enableForwarding(SSHClient client) async {
    await client.authAgent;
  }
}
```

- [ ] **Step 2: Update SshService to support agent auth**

In `ssh_service.dart`, the agent case in `connect()` already creates a basic client. Add agent forwarding after session is open:

```dart
// After _session = await client.shell(...)
if (config.authMethod == SshAuthMethod.agent) {
  try {
    await AgentForwardService.enableForwarding(client);
  } catch (_) {
    // Agent forwarding is optional; continue even if unavailable
  }
}
```

- [ ] **Step 3: Verify build**

```bash
cd ~/Builds/picshell && flutter analyze
```

- [ ] **Step 4: Commit**

```bash
cd ~/Builds/picshell && git add -A && git commit -m "feat: add SSH agent forwarding support"
```

---

## Task 13: Integration & Final Polish

**Files:**
- Modify: various files for integration fixes

- [ ] **Step 1: Run full analysis**

```bash
cd ~/Builds/picshell && flutter analyze
```

Fix any issues reported.

- [ ] **Step 2: Run all tests**

```bash
cd ~/Builds/picshell && flutter test
```

- [ ] **Step 3: Build APK to verify end-to-end**

```bash
cd ~/Builds/picshell && flutter build apk --debug
```

- [ ] **Step 4: Build iOS to verify (if on macOS)**

```bash
cd ~/Builds/picshell && flutter build ios --debug --no-codesign
```

- [ ] **Step 5: Commit**

```bash
cd ~/Builds/picshell && git add -A && git commit -m "chore: integration fixes and final polish"
```

---

## Notes for Implementing Agent

1. **Fork xterm.dart** — The plan forks `TerminalStudio/xterm.dart` v4.0.0 into `packages/xterm/`. The fork modifies `EscapeHandler` (add `unknownOSC`), `Terminal` (iTerm2 image assembly + storage), and `TerminalPainter` (image rendering on Canvas). All other xterm.dart functionality (VT100, cursor, scrolling, etc.) is preserved.

2. **iTerm2 OSC flow** — When xterm.dart's `EscapeParser` encounters an OSC sequence with code 1337, it calls `handler.unknownOSC(1337, payload)`. The `Terminal` class overrides this to parse `File=<params>;<base64>`, assemble chunks by `name`, decode to `ui.Image`, store in `iterm2Images`, and advance the cursor. The `TerminalPainter` draws images at their cursor row position.

3. **Image rendering position** — Images are placed at the cursor row when the ESC]1337 sequence completes. After decoding, the cursor is advanced by the image's row height so subsequent text appears below the image.

4. **File picker for key import** — The `file_picker` package requires platform-specific setup (Info.plist for iOS, etc.). Follow the package README for each platform.

5. **dartssh2 limitations** — Agent forwarding support in dartssh2 may be limited. Test early and fall back gracefully.

6. **Terminal cell metrics** — `cellHeight` in the fork defaults to 18.0 but should be measured from the actual font. `RenderTerminal` has `_cellWidth`/`_cellHeight` that should be exposed or passed through.
