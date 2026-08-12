import 'package:uuid/uuid.dart';

import '../models/forward_rule.dart';

const _uuid = Uuid();

/// One entry parsed from an OpenSSH `~/.ssh/config` file. Fields are populated
/// by [SshConfigParser.parse] as it walks the config; unknown keywords are
/// ignored. This is a pure data holder — tilde expansion and key import happen
/// in the import service, not here, so the parser stays side-effect free and
/// unit-testable on any platform.
class ParsedHost {
  final List<String> aliases;
  String? hostName;
  int? port;
  String? user;
  String? identityFilePath;
  String? proxyJump;
  final List<ForwardRule> forwards = [];

  ParsedHost({required this.aliases});

  /// First alias, used as the display name when importing.
  String get primaryAlias => aliases.isEmpty ? '?' : aliases.first;
}

/// Result of an import operation.
class ImportSummary {
  final int imported;
  final int skipped;
  final List<String> skippedNames;
  const ImportSummary({
    required this.imported,
    required this.skipped,
    this.skippedNames = const [],
  });
}

/// Parses OpenSSH config text into a list of [ParsedHost] entries.
///
/// Supported keywords: `Host`, `HostName`, `Port`, `User`, `IdentityFile`,
/// `ProxyJump`, `LocalForward`, `RemoteForward`, `DynamicForward`. Lines
/// starting with `#` and blank lines are ignored. `Include` is not supported.
///
/// Host blocks whose aliases contain wildcards (`*`, `?`, `!`) are dropped —
/// picshell resolves hosts by concrete alias, not by pattern. `IdentityFile`
/// paths are stored verbatim (tilde included); the caller expands them.
class SshConfigParser {
  static List<ParsedHost> parse(String text) {
    final hosts = <ParsedHost>[];
    ParsedHost? current;

    for (final raw in text.split('\n')) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      // OpenSSH treats ` #` (space-hash) as an inline comment delimiter.
      final commentAt = line.indexOf(' #');
      if (commentAt >= 0) line = line.substring(0, commentAt).trim();

      final match = _keywordRegex.firstMatch(line);
      if (match == null) continue;
      final keyword = match.group(1)!.toLowerCase();
      final args = line.substring(match.end).trim();
      if (args.isEmpty) continue;

      if (keyword == 'host') {
        if (current != null) hosts.add(current);
        current = ParsedHost(aliases: args.split(RegExp(r'\s+')));
      } else if (current != null) {
        _apply(current, keyword, args);
      }
    }
    if (current != null) hosts.add(current);

    // Drop wildcard host blocks (e.g. `Host *`); they match by pattern, not
    // by concrete name, so picshell cannot dial them directly.
    return hosts
        .where((h) => h.aliases.every(
              (a) => !a.contains('*') && !a.contains('?') && !a.contains('!'),
            ))
        .toList();
  }

  static final _keywordRegex = RegExp(r'^(\S+)\s*');

  static void _apply(ParsedHost host, String keyword, String args) {
    switch (keyword) {
      case 'hostname':
        host.hostName = args;
        break;
      case 'port':
        host.port = int.tryParse(args);
        break;
      case 'user':
        host.user = args;
        break;
      case 'identityfile':
        // Stored verbatim (may start with ~); the import service expands it
        // using the running platform's HOME.
        host.identityFilePath = args;
        break;
      case 'proxyjump':
        // Stored raw; the import service matches it against imported aliases.
        // May be `host`, `user@host`, or `host:port`.
        host.proxyJump = args;
        break;
      case 'localforward':
        _addForward(host, args, ForwardType.local);
        break;
      case 'remoteforward':
        _addForward(host, args, ForwardType.remote);
        break;
      case 'dynamicforward':
        _addDynamic(host, args);
        break;
      default:
        // Ignored: AddKeysToAgent, ServerAlive*, ForwardX11, etc.
        break;
    }
  }

  /// OpenSSH accepts two spellings for local/remote forwards:
  ///   `LocalForward 8080 db:5432`
  ///   `LocalForward 8080 db 5432`
  static void _addForward(ParsedHost host, String args, ForwardType type) {
    final parts = args.split(RegExp(r'\s+'));
    if (parts.isEmpty) return;
    final localPort = int.tryParse(parts[0]);
    if (localPort == null) return;

    String? remoteHost;
    int? remotePort;
    if (parts.length >= 2 && parts[1].contains(':')) {
      final hp = parts[1].split(':');
      remoteHost = hp.isNotEmpty ? hp[0] : null;
      remotePort = hp.length >= 2 ? int.tryParse(hp[1]) : null;
    } else if (parts.length >= 3) {
      remoteHost = parts[1];
      remotePort = int.tryParse(parts[2]);
    }

    host.forwards.add(ForwardRule(
      id: _uuid.v4(),
      type: type,
      localPort: localPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
      // Imported forwards default to manual start to avoid suddenly opening
      // dozens of listeners on first connect.
      autoStart: false,
    ));
  }

  static void _addDynamic(ParsedHost host, String args) {
    final port = int.tryParse(args.trim());
    if (port == null) return;
    host.forwards.add(ForwardRule(
      id: _uuid.v4(),
      type: ForwardType.socks,
      localPort: port,
      autoStart: false,
    ));
  }
}
