// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HostAdapter extends TypeAdapter<Host> {
  @override
  final int typeId = 0;

  @override
  Host read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Host(
      id: fields[0] as String,
      name: fields[1] as String,
      hostname: fields[2] as String,
      port: fields[3] as int,
      username: fields[4] as String,
      authType: fields[5] as AuthType,
      keyId: fields[6] as String?,
      password: fields[7] as String?,
      groupId: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Host obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.hostname)
      ..writeByte(3)
      ..write(obj.port)
      ..writeByte(4)
      ..write(obj.username)
      ..writeByte(5)
      ..write(obj.authType)
      ..writeByte(6)
      ..write(obj.keyId)
      ..writeByte(7)
      ..write(obj.password)
      ..writeByte(8)
      ..write(obj.groupId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HostAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AuthTypeAdapter extends TypeAdapter<AuthType> {
  @override
  final int typeId = 1;

  @override
  AuthType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AuthType.password;
      case 1:
        return AuthType.key;
      default:
        return AuthType.password;
    }
  }

  @override
  void write(BinaryWriter writer, AuthType obj) {
    switch (obj) {
      case AuthType.password:
        writer.writeByte(0);
        break;
      case AuthType.key:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
