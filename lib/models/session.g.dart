// GENERATED CODE — hand-maintained to match session.dart.
// If you edit Session, either update this file by hand or run:
//   dart run build_runner build --delete-conflicting-outputs
part of 'session.dart';

// ignore_for_file: type=lint

class SessionAdapter extends TypeAdapter<Session> {
  @override
  final int typeId = 1;

  @override
  Session read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final key = reader.readByte();
      fields[key] = reader.read();
    }
    return Session(
      id: fields[0] as String,
      appName: fields[1] as String,
      packageName: fields[2] as String,
      startTime: fields[3] as DateTime,
      endTime: fields[4] as DateTime,
      fpsSamples: _doubleList(fields[5]),
      cpuTempSamples: _doubleList(fields[6]),
      gpuTempSamples: _doubleList(fields[7]),
      freeRamSamples: _doubleList(fields[8]),
      cpuUsageSamples: _doubleList(fields[9]),
      gpuUsageSamples: _doubleList(fields[10]),
      storageSpeedSamples: _doubleList(fields[11]),
      batteryDropPercent: (fields[12] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  void write(BinaryWriter writer, Session obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.appName)
      ..writeByte(2)
      ..write(obj.packageName)
      ..writeByte(3)
      ..write(obj.startTime)
      ..writeByte(4)
      ..write(obj.endTime)
      ..writeByte(5)
      ..write(obj.fpsSamples)
      ..writeByte(6)
      ..write(obj.cpuTempSamples)
      ..writeByte(7)
      ..write(obj.gpuTempSamples)
      ..writeByte(8)
      ..write(obj.freeRamSamples)
      ..writeByte(9)
      ..write(obj.cpuUsageSamples)
      ..writeByte(10)
      ..write(obj.gpuUsageSamples)
      ..writeByte(11)
      ..write(obj.storageSpeedSamples)
      ..writeByte(12)
      ..write(obj.batteryDropPercent);
  }

  static List<double> _doubleList(dynamic v) {
    if (v == null) return <double>[];
    return (v as List).map((e) => (e as num).toDouble()).toList();
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}
