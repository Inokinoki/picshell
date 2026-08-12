import 'package:hive/hive.dart';

part 'forward_rule.g.dart';

/// Kind of SSH port forwarding a [ForwardRule] represents. Mirrors the
/// common OpenSSH command-line flags so the UI can label them directly.
@HiveType(typeId: 4)
enum ForwardType {
  /// Local forward (`ssh -L localPort:remoteHost:remotePort`). The client
  /// listens on [ForwardRule.localPort] and tunnels each incoming connection
  /// to [remoteHost]:[remotePort] through the SSH server.
  @HiveField(0)
  local,

  /// Remote forward (`ssh -R remotePort:localHost:localPort`). The server
  /// listens on [remotePort] and tunnels incoming connections back to the
  /// client's [localHost]:[localPort].
  @HiveField(1)
  remote,

  /// Dynamic SOCKS5 proxy (`ssh -D localPort`). The client listens on
  /// [localPort] and acts as a SOCKS5 server; the destination of each
  /// connection is chosen by the SOCKS client at runtime.
  @HiveField(2)
  socks,
}

/// A port-forwarding rule attached to a [Host]. Stored inline on the host so
/// a rule set always travels with its host and needs no cross-box reference.
///
/// Rules carry no secret material, so they bypass [SecretCipher] and live in
/// the same (already encrypted-at-rest by Hive) host box.
@HiveType(typeId: 5)
class ForwardRule extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final ForwardType type;

  /// Interface to bind the listener on. Usually '127.0.0.1'; use '0.0.0.0' to
  /// expose the tunnel on all interfaces (caveat emptor).
  @HiveField(2)
  final String localHost;

  /// Local port to listen on. Pass 0 to let the OS choose a free port; the
  /// actually bound port is reported back via the runtime forward state.
  @HiveField(3)
  final int localPort;

  /// Destination host for [ForwardType.local] / [ForwardType.remote].
  /// Unused (and should be null) for [ForwardType.socks].
  @HiveField(4)
  final String? remoteHost;

  /// Destination port for [ForwardType.local] / [ForwardType.remote].
  /// Unused (and should be null) for [ForwardType.socks].
  @HiveField(5)
  final int? remotePort;

  /// Whether the forward is started automatically once its session reaches the
  /// connected state. Independent of manual start/stop from the session view.
  @HiveField(6)
  final bool autoStart;

  ForwardRule({
    required this.id,
    required this.type,
    this.localHost = '127.0.0.1',
    required this.localPort,
    this.remoteHost,
    this.remotePort,
    this.autoStart = true,
  });

  /// Human-readable summary like `-L 8080:db.internal:5432` or `-D 1080`.
  String get summary {
    switch (type) {
      case ForwardType.local:
        return '-L $localPort:${remoteHost ?? '?'}:${remotePort ?? '?'}';
      case ForwardType.remote:
        return '-R $localPort:${remoteHost ?? '?'}:${remotePort ?? '?'}';
      case ForwardType.socks:
        return '-D $localPort';
    }
  }
}
