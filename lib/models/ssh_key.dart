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
