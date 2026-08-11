// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'known_host.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class KnownHostAdapter extends TypeAdapter<KnownHost> {
  @override
  final int typeId = 3;

  @override
  KnownHost read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return KnownHost(
      host: fields[0] as String,
      port: fields[1] as int,
      keyType: fields[2] as String,
      fingerprint: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, KnownHost obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.host)
      ..writeByte(1)
      ..write(obj.port)
      ..writeByte(2)
      ..write(obj.keyType)
      ..writeByte(3)
      ..write(obj.fingerprint);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KnownHostAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
