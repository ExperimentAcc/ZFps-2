import 'package:hive/hive.dart';

import '../utils/frame_stats.dart';

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

  /// Per-poll "1% low" FPS, same length as [fpsSamples] (-1 = unknown).
  /// Null for sessions recorded before frame-time stats existed.
  @HiveField(13)
  List<double>? lowFpsSamples;

  /// Frame-time histogram (see [FrameStats]). Null for older sessions.
  @HiveField(14)
  List<int>? frameTimeHist;

  /// True when FPS came from real per-frame timestamps; false when it was only
  /// estimated from the display refresh rate; null for older sessions.
  @HiveField(15)
  bool? realFrameData;

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
    this.lowFpsSamples,
    this.frameTimeHist,
    this.realFrameData,
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

  static bool _hasData(List<double> xs) => xs.any((e) => e >= 0);

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

  // -1 = no data (Fmt.temp shows "--" instead of a misleading 0°C)
  double get avgCpuTemp => _hasData(cpuTempSamples) ? _avg(cpuTempSamples) : -1;
  double get avgGpuTemp => _hasData(gpuTempSamples) ? _avg(gpuTempSamples) : -1;
  double get avgFreeRam => _avg(freeRamSamples);

  double get avgCpuUsage => _hasData(cpuUsageSamples) ? _avg(cpuUsageSamples) : -1;
  double get maxCpuUsage => _hasData(cpuUsageSamples) ? _max(cpuUsageSamples) : -1;

  double get avgGpuUsage => _hasData(gpuUsageSamples) ? _avg(gpuUsageSamples) : -1;
  double get maxGpuUsage => _hasData(gpuUsageSamples) ? _max(gpuUsageSamples) : -1;

  double get avgStorageSpeed => _avg(storageSpeedSamples);

  int get sampleCount => fpsSamples.length;

  // ------------------------------------------------------- frame-time stats

  List<double> get lows => lowFpsSamples ?? const <double>[];

  /// True when this session has usable frame-time data.
  bool get hasFrameData =>
      realFrameData == true &&
      frameTimeHist != null &&
      FrameStats.totalFrames(frameTimeHist!) >= 30;

  /// FPS equivalent of the slowest 1% of frames (null when unavailable).
  double? get onePercentLow =>
      hasFrameData ? FrameStats.lowFps(frameTimeHist!, 0.01) : null;

  /// FPS equivalent of the slowest 0.1% of frames (null when unavailable).
  double? get pointOnePercentLow =>
      hasFrameData ? FrameStats.lowFps(frameTimeHist!, 0.001) : null;

  /// Average frame time in milliseconds (null when unavailable).
  double? get avgFrameTimeMs =>
      hasFrameData ? FrameStats.avgFrameMs(frameTimeHist!) : null;
}
