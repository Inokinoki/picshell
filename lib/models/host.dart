import 'package:hive/hive.dart';
import 'forward_rule.dart';

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

  /// Optional id of another [Host] used as a jump host (ProxyJump, `ssh -J`).
  /// Null means connect directly. Single hop is exposed in the UI, but the
  /// nested proxy-config structure already supports future multi-hop chains.
  @HiveField(9)
  String? proxyHostId;

  /// Port-forwarding rules attached to this host. Rules whose
  /// [ForwardRule.autoStart] is true are (re)started whenever the session
  /// (re)connects; any rule can also be toggled manually from the session view.
  @HiveField(10)
  List<ForwardRule> forwards;

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
    this.proxyHostId,
    List<ForwardRule>? forwards,
  }) : forwards = forwards ?? const [];

  /// Returns a copy with the given fields replaced. The id is immutable and
  /// therefore not overridable. Used by [HostStore]'s encrypt/decrypt path so
  /// that adding a new field only requires touching this single method.
  Host copyWith({
    String? name,
    String? hostname,
    int? port,
    String? username,
    AuthType? authType,
    String? keyId,
    String? password,
    String? groupId,
    String? proxyHostId,
    List<ForwardRule>? forwards,
  }) {
    return Host(
      id: id,
      name: name ?? this.name,
      hostname: hostname ?? this.hostname,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      keyId: keyId ?? this.keyId,
      password: password ?? this.password,
      groupId: groupId ?? this.groupId,
      proxyHostId: proxyHostId ?? this.proxyHostId,
      forwards: forwards ?? this.forwards,
    );
  }
}

@HiveType(typeId: 1)
enum AuthType {
  @HiveField(0)
  password,
  @HiveField(1)
  key,
  @HiveField(2)
  agent,
}
