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
