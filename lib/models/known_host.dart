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

  /// Hex-encoded fingerprint of the host public key (as given by dartssh2's
  /// `onVerifyHostKey` callback, currently MD5 of the raw key bytes).
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
