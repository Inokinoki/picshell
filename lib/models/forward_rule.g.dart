// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'forward_rule.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ForwardRuleAdapter extends TypeAdapter<ForwardRule> {
  @override
  final int typeId = 5;

  @override
  ForwardRule read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ForwardRule(
      id: fields[0] as String,
      type: fields[1] as ForwardType,
      localHost: fields[2] as String,
      localPort: fields[3] as int,
      remoteHost: fields[4] as String?,
      remotePort: fields[5] as int?,
      autoStart: fields[6] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, ForwardRule obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.localHost)
      ..writeByte(3)
      ..write(obj.localPort)
      ..writeByte(4)
      ..write(obj.remoteHost)
      ..writeByte(5)
      ..write(obj.remotePort)
      ..writeByte(6)
      ..write(obj.autoStart);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForwardRuleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ForwardTypeAdapter extends TypeAdapter<ForwardType> {
  @override
  final int typeId = 4;

  @override
  ForwardType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ForwardType.local;
      case 1:
        return ForwardType.remote;
      case 2:
        return ForwardType.socks;
      default:
        return ForwardType.local;
    }
  }

  @override
  void write(BinaryWriter writer, ForwardType obj) {
    switch (obj) {
      case ForwardType.local:
        writer.writeByte(0);
        break;
      case ForwardType.remote:
        writer.writeByte(1);
        break;
      case ForwardType.socks:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForwardTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
