import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../database/app_database.dart';
import '../models/device_stats.dart';
import '../models/session.dart';
import 'notification_service.dart';
import 'overlay_service.dart';
import 'shizuku_service.dart';

/// Owns the lifecycle of a monitoring session: start → poll every 2 s →
/// stop → persist a [Session] to Hive → fire the completion notification.
class MonitorService extends ChangeNotifier {
  MonitorService._();
  static final MonitorService instance = MonitorService._();

  static const Duration pollInterval = Duration(seconds: 2);

  static const MethodChannel _channel =
      MethodChannel('com.zsdev.fpsmonitor/channel');

  Timer? _pollTimer;

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

    // First poll immediately (also warms up the storage benchmark), then every 2 s
    await _poll();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => _poll());
    return true;
  }

  Future<Session?> stopSession() async {
    if (!_isMonitoring) return null;

    _pollTimer?.cancel();
    _pollTimer = null;

    // One final sample + battery reading
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
      fpsSamples: List<double>.of(_fpsSamples),
      cpuTempSamples: List<double>.of(_cpuTempSamples),
      gpuTempSamples: List<double>.of(_gpuTempSamples),
      freeRamSamples: List<double>.of(_freeRamSamples),
      cpuUsageSamples: List<double>.of(_cpuUsageSamples),
      gpuUsageSamples: List<double>.of(_gpuUsageSamples),
      storageSpeedSamples: List<double>.of(_storageSpeedSamples),
      batteryDropPercent: batteryDrop,
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

      _current = merged;
      _record(merged);
      await OverlayService.instance.updateOverlay(merged);
    } catch (e) {
      debugPrint('Poll failed: $e');
    }
    notifyListeners();
  }

  void _record(DeviceStats s) {
    void add(List<double> target, double v) {
      if (v >= 0) target.add(v);
    }

    add(_fpsSamples, s.fps);
    add(_cpuTempSamples, s.cpuTemp);
    add(_gpuTempSamples, s.gpuTemp);
    add(_freeRamSamples, s.freeRamMb);
    add(_cpuUsageSamples, s.cpuUsage);
    add(_gpuUsageSamples, s.gpuUsage);
    add(_storageSpeedSamples, s.storageSpeed);
  }

  void _resetSamples() {
    _fpsSamples.clear();
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
