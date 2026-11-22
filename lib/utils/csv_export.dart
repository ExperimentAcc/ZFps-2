import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/session.dart';

/// Builds CSV exports of saved sessions.
///
/// * [allSessions]    one summary row per session
/// * [sessionSamples] the time series of a single session (one row per 2 s poll)
///
/// Files are UTF-8 with a BOM so Excel opens game names with any characters.
class CsvExport {
  CsvExport._();

  /// Seconds between two samples (matches MonitorService.pollInterval).
  static const int stepSeconds = 2;

  // ------------------------------------------------------------ public API

  static Uint8List allSessions(List<Session> sessions) {
    final b = StringBuffer()
      ..writeln(_row([
        'id',
        'app',
        'package',
        'start_time_local',
        'end_time_local',
        'duration_s',
        'avg_fps',
        'min_fps',
        'max_fps',
        'one_percent_low_fps',
        'point1_percent_low_fps',
        'avg_frame_time_ms',
        'avg_cpu_temp_c',
        'avg_gpu_temp_c',
        'avg_cpu_usage_pct',
        'max_cpu_usage_pct',
        'avg_gpu_usage_pct',
        'max_gpu_usage_pct',
        'avg_free_ram_mb',
        'avg_storage_mb_s',
        'battery_drop_pct',
        'fps_samples',
        'fps_source',
      ]));

    for (final s in sessions) {
      b.writeln(_row([
        s.id,
        s.appName,
        s.packageName,
        _ts(s.startTime),
        _ts(s.endTime),
        s.duration.inSeconds,
        _pos(s.avgFps),
        _pos(s.minFps),
        _pos(s.maxFps),
        _n(s.onePercentLow),
        _n(s.pointOnePercentLow),
        _n(s.avgFrameTimeMs, 2),
        _n(s.avgCpuTemp),
        _n(s.avgGpuTemp),
        _n(s.avgCpuUsage),
        _n(s.maxCpuUsage),
        _n(s.avgGpuUsage),
        _n(s.maxGpuUsage),
        _pos(s.avgFreeRam, 0),
        _pos(s.avgStorageSpeed),
        _n(s.batteryDropPercent, 0),
        s.fpsSamples.length,
        _source(s),
      ]));
    }
    return _encode(b.toString());
  }

  static Uint8List sessionSamples(Session s) {
    // FPS samples only start once the game's frames show up; the other metrics
    // are recorded from the first poll, so shift FPS by that offset.
    final start = s.fpsStartPoll ?? 0;
    final lows = s.lows;
    final rows = [
      start + s.fpsSamples.length,
      s.cpuTempSamples.length,
      s.gpuTempSamples.length,
      s.freeRamSamples.length,
      s.cpuUsageSamples.length,
      s.gpuUsageSamples.length,
      s.storageSpeedSamples.length,
    ].reduce(math.max);

    final b = StringBuffer()
      ..writeln(_row([
        'sample',
        'time_s',
        'fps',
        'one_percent_low_fps',
        'cpu_temp_c',
        'gpu_temp_c',
        'free_ram_mb',
        'cpu_usage_pct',
        'gpu_usage_pct',
        'storage_mb_s',
      ]));

    for (var i = 0; i < rows; i++) {
      final j = i - start;
      final hasFps = j >= 0 && j < s.fpsSamples.length;
      b.writeln(_row([
        i + 1,
        i * stepSeconds,
        hasFps ? _n(s.fpsSamples[j]) : '',
        (hasFps && j < lows.length) ? _n(lows[j]) : '',
        _at(s.cpuTempSamples, i),
        _at(s.gpuTempSamples, i),
        _at(s.freeRamSamples, i, 0),
        _at(s.cpuUsageSamples, i),
        _at(s.gpuUsageSamples, i),
        _at(s.storageSpeedSamples, i),
      ]));
    }
    return _encode(b.toString());
  }

  /// "FPS-Monitor_<game>_<yyyyMMdd-HHmm>" (no extension) for file names.
  static String baseName(Session s) {
    final t = s.startTime.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
    var slug = s.appName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) slug = 'session';
    if (slug.length > 40) slug = slug.substring(0, 40);
    return 'FPS-Monitor_${slug}_$stamp';
  }

  static String allSessionsFileName() {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'FPS-Monitor_all-sessions_${t.year}${two(t.month)}${two(t.day)}.csv';
  }

  // ------------------------------------------------------------ helpers

  static Uint8List _encode(String csv) =>
      Uint8List.fromList(utf8.encode('\uFEFF$csv'));

  static String _cell(Object? v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _row(List<Object?> cells) => cells.map(_cell).join(',');

  /// Number with [digits] decimals; empty when unknown (null or negative).
  static String _n(double? v, [int digits = 1]) =>
      (v == null || v < 0) ? '' : v.toStringAsFixed(digits);

  /// Like [_n] but also treats 0 as "no data" (used for averages of empty lists).
  static String _pos(double v, [int digits = 1]) =>
      v > 0 ? v.toStringAsFixed(digits) : '';

  static String _at(List<double> list, int i, [int digits = 1]) =>
      i < list.length ? _n(list[i], digits) : '';

  static String _ts(DateTime t) => t.toLocal().toIso8601String().split('.').first;

  static String _source(Session s) {
    switch (s.realFrameData) {
      case true:
        return 'real_frames';
      case false:
        return 'refresh_rate_estimate';
      default:
        return 'unknown_legacy';
    }
  }
}
