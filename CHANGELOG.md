# Changelog

All notable changes to picshell are documented here.

## 1.0.0 — feature integration

First consolidated release: the full feature stack plus the desktop
stability pass, verified end-to-end against a real OpenSSH server
(unit: 388 tests; macOS e2e: launch, SSH, TOFU, graphics, SFTP,
search, forwards, vault).

### SSH core

- **SSH sessions with password / private key / ssh-agent auth**
  (dartssh2 2.22.5, pointycastle 4.0.0 — required for current stable
  Dart SDKs).
- **Trust-on-first-use host key verification.** First contact with a
  host shows a dialog with the real `SHA256:<base64>` fingerprint
  (matching `ssh-keygen -l`; dartssh2 ≥ 2.22 fingerprints are
  normalised instead of double-hex-encoded). Key changes surface a
  MITM warning; stale-format records re-prompt instead.
- **ProxyJump (ssh -J)** with per-hop TOFU verification; jump chains
  are refused explicitly. Agent auth is supported for direct
  connections.
- **`~/.ssh/config` import** with auto-discovery, plus file/paste
  import paths.
- **Auto-reconnect** with exponential backoff (1s → 30s cap).
  Terminal I/O is bound to the session's *current* transport, so
  keystrokes survive a reconnect, and reconnect storms are prevented
  by not emitting a synthetic "disconnected" state at connect time.
- Host key records are pinned per host/port/key-type in a Hive-backed
  known-hosts store (typeId 6 — resolves the typeId collision with
  Session that crashed the app at startup).

### Terminal

- **Scrollback search** (Ctrl+Shift+F): match count, next/previous
  navigation, case toggle, regex mode, streaming-refresh that keeps
  anchors stable as output shifts lines; highlight/anchor disposal is
  leak-free across re-searches and scrollback wraps.
- **Kitty graphics protocol (APC `G`)**, **Sixel (DCS)** and
  **iTerm2 OSC 1337** inline images, rendered as floating overlays
  with drag, pinch, Option/Alt+wheel zoom and corner-resize. Images
  honour requested dimensions including iTerm2 cell/percent units;
  decode is bounded (4096 px cap) and raw bytes budgeted (LRU, 64 MiB).
- OSC payload parsing hardened: semicolon-aware 4 MiB cap with
  consume-on-overflow, split-ESC safe, and bounded APC/DCS buffers —
  hostile remote output can't grow memory unboundedly or leak escape
  fragments into the grid.
- Viewport stays pinned to the live screen across ConPTY buffer
  clears; scrolling up unpins, returning to the bottom resumes.
- Terminal colour schemes (8 palettes), font family/size, line
  height; keyboard-bar auto/always/hidden modes.
- Desktop input: printable characters come straight from hardware key
  events on Windows/Linux (Windows' hidden text field drops them),
  and the terminal takes focus on launch and session switches.

### Files & networking

- **SFTP file browser**: list, navigate, create, rename, delete,
  upload and download, with corrupt-hostkey handling that records the
  rejection instead of hanging the upload writer; mid-upload errors
  propagate instead of hanging.
- **Local / remote / SOCKS5-dynamic port forwarding** with a
  per-session status sheet, manual start/stop and auto-start rules.
  SOCKS5 answers CONNECT (IPv4, domain), rejects unsupported auth
  methods, and drops stalled handshakes at a deadline.
- **Auto-reconnect applies to forwards**: rules are re-bound when the
  session reconnects.

### Security

- **Credential vault**: a device-bound master key gated by biometrics
  encrypts saved passwords and key passphrases at rest (Hive records
  re-encrypted in place). Launch performs a verified unlock with a
  crash-safe re-encryption path for interrupted enables, a visible
  warning if the gate had to be bypassed, and re-lock on background.
  Toggling the vault (either direction) requires a successful user
  verification.
- macOS debug builds without the keychain entitlement degrade
  gracefully (secrets stay unencrypted, warning logged).

### Desktop (macOS/Windows/Linux)

- Real pty geometry stays in sync with the terminal viewport; the
  app restores window/session geometry.
- Saved-host edits honour every field, forms validate (port range,
  required fields, key selection), and stale deep-link ids land on a
  "Host Not Found" screen instead of crashing.
- Windows-specific fixes: correct key lookup in the agent path and
  printable-input handling above.

### Tests & CI

- macOS integration suite: app launch, real-sshd connection, OSC 1337
  floating image, SFTP list/download, scrollback search, appearance,
  local-forward round-trip, vault flow.
- Android CI integration job runs against a throwaway sshd container
  (`Dockerfile.sshd`, ports 2222 external / 22 in-container for the
  SOCKS tunnel tests); vendored `packages/xterm` excluded from root
  analysis; flutter_lints declared and applied.
