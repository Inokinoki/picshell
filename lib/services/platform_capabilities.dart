import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Platform capability detection for picshell.
///
/// Centralises every "mobile vs desktop" branch so the UI reads booleans
/// instead of scattering `Platform.is*` calls across the codebase. Every
/// getter is guarded by [kIsWeb] so it is safe to call on Flutter Web too,
/// where `dart:io` Platform throws.
///
/// Why this exists:
/// - Mobile (iOS/Android) sandboxes have no `~/.ssh/` and suspend background
///   sockets within seconds of the app being backgrounded.
/// - Desktop (macOS/Linux/Windows) can read a real OpenSSH config and keep
///   tunnels alive while unfocused.
///
/// Code that needs to branch on these constraints should call the getters
/// below rather than reaching for `Platform` directly.

/// True on macOS, Linux or Windows (native, not web).
bool get isDesktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

/// True on iOS or Android (native, not web).
bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Whether the platform exposes a user-readable OpenSSH config at a
/// conventional path. Mobile sandboxes have no `~/.ssh/`, so config import
/// there must rely on file pickers or pasted text instead of auto-discovery.
bool get canReadSystemSshConfig => isDesktop;

/// Whether port-forwarding tunnels can be expected to survive the app going
/// to the background. iOS/Android freeze background sockets within seconds;
/// only desktop platforms keep tunnels alive while unfocused. UI that manages
/// forwards should surface this limitation on mobile.
bool get supportsBackgroundForward => isDesktop;

/// Default OpenSSH config path on desktop platforms (`~/.ssh/config`), or
/// null when there is no conventional location (mobile/web or no HOME set).
/// On Windows, falls back to `%USERPROFILE%\.ssh\config`.
String? get sshConfigDefaultPath {
  if (!isDesktop) return null;
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return null;
  return '$home/.ssh/config';
}
