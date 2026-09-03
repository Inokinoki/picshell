import 'package:hive/hive.dart';

part 'known_host.g.dart';

/// A pinned SSH host key for TOFU (trust-on-first-use) verification.
/// typeId 6: 0-5 are taken by Host/AuthType/SshKey/Session/ForwardType/
/// ForwardRule; the old value 3 collided with Session and crashed main().
@HiveType(typeId: 6)
class KnownHost extends HiveObject {
  @HiveField(0)
  final String host;

  @HiveField(1)
  final int port;

  @HiveField(2)
  final String keyType;

  /// Canonical fingerprint string, e.g. `SHA256:<base64>` (what dartssh2
  /// >= 2.22 presents) or `MD5:aa:bb:...` — see
  /// `canonicalHostKeyFingerprint`.
  @HiveField(3)
  final String fingerprint;

  KnownHost({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
  });

  /// Box key used to look up a host entry: `host:port`.
  String get boxKey => '$host:$port';
}
