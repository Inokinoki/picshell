import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/host.dart';
import '../providers/host_provider.dart';
import '../providers/key_provider.dart';
import 'key_import_service.dart';
import 'platform_capabilities.dart';
import 'ssh_config_parser.dart';

const _uuid = Uuid();

/// Coordinates parsing of OpenSSH config text and persistence of the result
/// into picshell's host/key stores. Pure parsing lives in [SshConfigParser];
/// this service handles the side effects (file reads, store writes, alias
/// matching) and is therefore only called from the UI layer.
class SshConfigImportService {
  /// Parses [text] and imports each parsed host. Hosts whose alias collides
  /// with an existing (or already-imported-this-run) name are skipped.
  ///
  /// On desktop ([canReadSystemSshConfig]), each `IdentityFile` is loaded and
  /// stored as an SSH key; on mobile the path is ignored (no sandbox access).
  /// `ProxyJump` aliases are matched against freshly imported hosts.
  static Future<ImportSummary> importText(String text, WidgetRef ref) async {
    final parsed = SshConfigParser.parse(text);
    final hostNotifier = ref.read(hostListProvider.notifier);
    final existing = ref.read(hostListProvider);
    final existingNames = existing.map((h) => h.name).toSet();

    final imported = <Host>[];
    final skipped = <String>[];

    // Pass 1: import each host, resolving IdentityFile → keyId where possible.
    for (final p in parsed) {
      final alias = p.primaryAlias;
      if (existingNames.contains(alias) ||
          imported.any((h) => h.name == alias)) {
        skipped.add(alias);
        continue;
      }

      String? keyId;
      if (p.identityFilePath != null && canReadSystemSshConfig) {
        keyId = await _importIdentityFile(p.identityFilePath!, ref);
      }

      final host = Host(
        id: _uuid.v4(),
        name: alias,
        hostname: p.hostName ?? alias,
        port: p.port ?? 22,
        username: p.user ?? '',
        authType: keyId != null ? AuthType.key : AuthType.password,
        keyId: keyId,
        forwards: List.of(p.forwards),
      );
      await hostNotifier.add(host);
      imported.add(host);
    }

    // Pass 2: resolve ProxyJump tokens against imported hosts (by alias or
    // HostName). Done after pass 1 so jump targets exist even if declared
    // later in the file. Self-references are skipped.
    for (final p in parsed.where((p) => p.proxyJump != null)) {
      final host =
          imported.where((h) => h.name == p.primaryAlias).firstOrNull;
      if (host == null) continue; // skipped or wildcard-dropped
      final token = _extractHostToken(p.proxyJump!);
      final jump = imported
          .where((h) => h.name == token || h.hostname == token)
          .firstOrNull;
      if (jump != null && jump.id != host.id) {
        host.proxyHostId = jump.id;
        await hostNotifier.update(host);
      }
    }

    return ImportSummary(
      imported: imported.length,
      skipped: skipped.length,
      skippedNames: skipped,
    );
  }

  /// Reads [path] (expanding `~`), parses it as a private key, and stores it.
  /// Returns the new key id, or null if the file is missing, the key is
  /// encrypted, or parsing fails — these are expected and silently skipped.
  static Future<String?> _importIdentityFile(
    String path,
    WidgetRef ref,
  ) async {
    final expanded = _expandTilde(path);
    try {
      final pem = await File(expanded).readAsString();
      final name = expanded.split(Platform.pathSeparator).last;
      final key = KeyImportService.fromPem(name, pem);
      await ref.read(keyListProvider.notifier).add(key);
      return key.id;
    } catch (_) {
      return null;
    }
  }

  /// Expands a leading `~` using the running platform's HOME / USERPROFILE.
  static String _expandTilde(String path) {
    if (!path.startsWith('~')) return path;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    if (home.isEmpty) return path;
    if (path == '~') return home;
    if (path.startsWith('~/')) return '$home${path.substring(1)}';
    return path; // `~user` form is not expanded.
  }

  /// Extracts the host token from a ProxyJump value like `user@host:2222`.
  static String _extractHostToken(String proxyJump) {
    var t = proxyJump;
    if (t.contains('@')) t = t.substring(t.lastIndexOf('@') + 1);
    if (t.contains(':')) t = t.substring(0, t.indexOf(':'));
    return t;
  }
}
