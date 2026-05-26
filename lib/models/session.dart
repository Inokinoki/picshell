import 'package:hive/hive.dart';

part 'session.g.dart';

@HiveType(typeId: 3)
class Session extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String hostId;

  @HiveField(2)
  DateTime lastActive;

  Session({required this.id, required this.hostId, required this.lastActive});
}
