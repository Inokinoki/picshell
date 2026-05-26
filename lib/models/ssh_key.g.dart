// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ssh_key.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SshKeyAdapter extends TypeAdapter<SshKey> {
  @override
  final int typeId = 2;

  @override
  SshKey read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SshKey(
      id: fields[0] as String,
      name: fields[1] as String,
      privateKeyPem: fields[2] as String,
      publicKey: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, SshKey obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.privateKeyPem)
      ..writeByte(3)
      ..write(obj.publicKey);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshKeyAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
