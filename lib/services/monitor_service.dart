import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../database/app_database.dart';
import '../models/device_stats.dart';
import '../models/session.dart';
import '../utils/frame_stats.dart';
import 'notification_service.dart';
import 'overlay_service.dart';
import 'shizuku_service.dart';

/// Owns the lifecycle of a monitoring session: start → poll every 2 s →
/// stop → persist a [Session] to Hive → fire the completion notification.
class MonitorService extends ChangeNotifier {
  MonitorService._();
  static final MonitorService instance = MonitorService._();

  static const Duration pollInterval = Duration(seconds: 2);

  /// Frame timestamps are read more often than the other stats so no frames
  /// are missed on high refresh-rate screens (SurfaceFlinger keeps ~127 frames).
  static const Duration framePollInterval = Duration(milliseconds: 500);

  static const MethodChannel _channel =
      MethodChannel('com.zsdev.fpsmonitor/channel');

  Timer? _pollTimer;
  Timer? _frameTimer;
  bool _frameBusy = false;
  bool _frameReset = true;

  /// True once real per-frame data has been read in this session.
  bool _realFrames = false;

  bool _isMonitoring = false;
  String? _appName;
  String? _packageName;
  DateTime? _startTime;

  DeviceStats? _current;
  double? _lastStorageSpeed;
  int _pollCount = 0;
  int _batteryStart = -1;
  int _batteryEnd = -1;

  final List<double> _fpsSamples = [];
  final List<double> _lowSamples = [];

  /// Refresh-rate based FPS, only kept as a fallback if real frame data never arrives.
  final List<double> _fallbackFpsSamples = [];

  /// Frame times collected since the last 2 s poll.
  final List<double> _windowFrames = [];
  List<int> _frameHist = FrameStats.emptyHistogram();
  final List<double> _cpuTempSamples = [];
  final List<double> _gpuTempSamples = [];
  final List<double> _freeRamSamples = [];
  final List<double> _cpuUsageSamples = [];
  final List<double> _gpuUsageSamples = [];
  final List<double> _storageSpeedSamples = [];

  // -------------------------------------------------------------- getters

  bool get isMonitoring => _isMonitoring;
  String? get appName => _appName;
  String? get packageName => _packageName;
  DateTime? get startTime => _startTime;
  DeviceStats? get current => _current;
  int get pollCount => _pollCount;

  Duration get elapsed =>
      _startTime == null ? Duration.zero : DateTime.now().difference(_startTime!);

  // -------------------------------------------------------------- session

  Future<bool> startSession({
    required String appName,
    required String packageName,
  }) async {
    if (_isMonitoring) return false;

    _resetSamples();
    _batteryStart = await ShizukuService.instance.getBatteryLevel();
    _batteryEnd = -1;
    _appName = appName;
    _packageName = packageName;
    _startTime = DateTime.now();
    _pollCount = 0;
    _lastStorageSpeed = null;

    // Foreground service (keeps process alive) + floating overlay
    await _invokeBool('startMonitoring', {'appName': appName});

    _isMonitoring = true;
    notifyListeners();

    // First frame read + stats poll immediately (also warms up the storage
    // benchmark), then frames every 0.5 s and the other stats every 2 s
    await _pollFrames();
    await _poll();
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(framePollInterval, (_) => _pollFrames());
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => _poll());
    return true;
  }

  Future<Session?> stopSession() async {
    if (!_isMonitoring) return null;

    _pollTimer?.cancel();
    _pollTimer = null;
    _frameTimer?.cancel();
    _frameTimer = null;

    // One final sample + battery reading
    await _pollFrames();
    await _poll();
    _batteryEnd = await ShizukuService.instance.getBatteryLevel();

    await _invokeBool('stopMonitoring', const {});

    final batteryDrop = (_batteryStart >= 0 && _batteryEnd >= 0 && _batteryStart >= _batteryEnd)
        ? (_batteryStart - _batteryEnd).toDouble()
        : 0.0;

    final session = Session(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      appName: _appName ?? 'Unknown',
      packageName: _packageName ?? '',
      startTime: _startTime ?? DateTime.now(),
      endTime: DateTime.now(),
      fpsSamples: List<double>.of(_realFrames ? _fpsSamples : _fallbackFpsSamples),
      cpuTempSamples: List<double>.of(_cpuTempSamples),
      gpuTempSamples: List<double>.of(_gpuTempSamples),
      freeRamSamples: List<double>.of(_freeRamSamples),
      cpuUsageSamples: List<double>.of(_cpuUsageSamples),
      gpuUsageSamples: List<double>.of(_gpuUsageSamples),
      storageSpeedSamples: List<double>.of(_storageSpeedSamples),
      batteryDropPercent: batteryDrop,
      lowFpsSamples: _realFrames ? List<double>.of(_lowSamples) : null,
      frameTimeHist: _realFrames ? List<int>.of(_frameHist) : null,
      realFrameData: _realFrames,
    );

    try {
      await AppDatabase.instance.saveSession(session);
    } catch (e) {
      debugPrint('Failed to persist session: $e');
    }

    await NotificationService.instance.showSessionComplete(session);

    _isMonitoring = false;
    _startTime = null;
    notifyListeners();
    return session;
  }

  // ------------------------------------------------------------ polling

  Future<void> _poll() async {
    final pkg = _packageName;
    if (pkg == null) return;
    _pollCount++;

    // Benchmark storage only on the first sample and then every 5th (~10 s)
    final includeStorage = _pollCount == 1 || _pollCount % 5 == 0;

    try {
      final stats = await ShizukuService.instance
          .collectStats(pkg, includeStorage: includeStorage);

      if (stats.storageSpeed >= 0) {
        _lastStorageSpeed = stats.storageSpeed;
      }
      final merged = (_lastStorageSpeed != null && stats.storageSpeed < 0)
          ? stats.copyWith(storageSpeed: _lastStorageSpeed)
          : stats;

      // Frames collected since the previous poll -> real FPS + 1% low for this window
      final window = List<double>.of(_windowFrames);
      _windowFrames.clear();

      var stats0 = merged;
      double? low;
      if (_realFrames) {
        // Real frame data wins. No frames in a window means nothing was drawn (0 FPS).
        stats0 = merged.copyWith(fps: FrameStats.fpsOf(window) ?? 0.0);
        low = FrameStats.lowFpsOfList(window, 0.01);
      }

      _current = stats0;
      _record(stats0, real: _realFrames, low: low);
      await OverlayService.instance.updateOverlay(stats0);
    } catch (e) {
      debugPrint('Poll failed: $e');
    }
    notifyListeners();
  }

  Future<void> _pollFrames() async {
    final pkg = _packageName;
    if (pkg == null || _frameBusy) return;
    _frameBusy = true;
    try {
      final reset = _frameReset;
      _frameReset = false;
      final batch = await ShizukuService.instance.pollFrames(pkg, reset: reset);
      if (batch.valid) {
        _realFrames = true;
        if (batch.frameTimesMs.isNotEmpty) {
          _windowFrames.addAll(batch.frameTimesMs);
          FrameStats.addAll(_frameHist, batch.frameTimesMs);
        }
      }
    } catch (e) {
      debugPrint('Frame poll failed: $e');
    } finally {
      _frameBusy = false;
    }
  }

  void _record(DeviceStats s, {required bool real, double? low}) {
    void add(List<double> target, double v) {
      if (v >= 0) target.add(v);
    }

    if (s.fps >= 0) {
      if (real) {
        _fpsSamples.add(s.fps);
        _lowSamples.add(low ?? -1); // keeps both lists aligned
      } else {
        _fallbackFpsSamples.add(s.fps);
      }
    }
    add(_cpuTempSamples, s.cpuTemp);
    add(_gpuTempSamples, s.gpuTemp);
    add(_freeRamSamples, s.freeRamMb);
    add(_cpuUsageSamples, s.cpuUsage);
    add(_gpuUsageSamples, s.gpuUsage);
    add(_storageSpeedSamples, s.storageSpeed);
  }

  void _resetSamples() {
    _fpsSamples.clear();
    _lowSamples.clear();
    _fallbackFpsSamples.clear();
    _windowFrames.clear();
    _frameHist = FrameStats.emptyHistogram();
    _frameReset = true;
    _frameBusy = false;
    _realFrames = false;
    _cpuTempSamples.clear();
    _gpuTempSamples.clear();
    _freeRamSamples.clear();
    _cpuUsageSamples.clear();
    _gpuUsageSamples.clear();
    _storageSpeedSamples.clear();
    _current = null;
  }

  Future<bool> _invokeBool(String method, Map<String, dynamic> args) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
