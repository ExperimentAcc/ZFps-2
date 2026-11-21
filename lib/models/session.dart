import 'package:hive/hive.dart';

part 'session.g.dart';

/// A completed (or in-progress) monitoring session, persisted with Hive.
@HiveType(typeId: 1)
class Session extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String appName;

  @HiveField(2)
  String packageName;

  @HiveField(3)
  DateTime startTime;

  @HiveField(4)
  DateTime endTime;

  @HiveField(5)
  List<double> fpsSamples;

  @HiveField(6)
  List<double> cpuTempSamples;

  @HiveField(7)
  List<double> gpuTempSamples;

  @HiveField(8)
  List<double> freeRamSamples;

  @HiveField(9)
  List<double> cpuUsageSamples;

  @HiveField(10)
  List<double> gpuUsageSamples;

  @HiveField(11)
  List<double> storageSpeedSamples;

  /// Battery percentage points drained over the session (can be 0).
  @HiveField(12)
  double batteryDropPercent;

  Session({
    required this.id,
    required this.appName,
    required this.packageName,
    required this.startTime,
    required this.endTime,
    required this.fpsSamples,
    required this.cpuTempSamples,
    required this.gpuTempSamples,
    required this.freeRamSamples,
    required this.cpuUsageSamples,
    required this.gpuUsageSamples,
    required this.storageSpeedSamples,
    required this.batteryDropPercent,
  });

  // ------------------------------------------------------------ durations

  Duration get duration => endTime.difference(startTime);

  String get durationFormatted {
    final d = duration;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    }
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  // ------------------------------------------------------- averages (≥ 0)

  static double _avg(List<double> xs) {
    final valid = xs.where((e) => e >= 0).toList();
    if (valid.isEmpty) return 0;
    return valid.reduce((a, b) => a + b) / valid.length;
  }

  static double _max(List<double> xs) {
    final valid = xs.where((e) => e >= 0).toList();
    if (valid.isEmpty) return 0;
    return valid.reduce((a, b) => a > b ? a : b);
  }

  static double _min(List<double> xs) {
    final valid = xs.where((e) => e >= 0).toList();
    if (valid.isEmpty) return 0;
    return valid.reduce((a, b) => a < b ? a : b);
  }

  double get avgFps => _avg(fpsSamples);
  double get maxFps => _max(fpsSamples);
  double get minFps => _min(fpsSamples);

  double get avgCpuTemp => _avg(cpuTempSamples);
  double get avgGpuTemp => _avg(gpuTempSamples);
  double get avgFreeRam => _avg(freeRamSamples);

  double get avgCpuUsage => _avg(cpuUsageSamples);
  double get maxCpuUsage => _max(cpuUsageSamples);

  double get avgGpuUsage => _avg(gpuUsageSamples);
  double get maxGpuUsage => _max(gpuUsageSamples);

  double get avgStorageSpeed => _avg(storageSpeedSamples);

  int get sampleCount => fpsSamples.length;
}
