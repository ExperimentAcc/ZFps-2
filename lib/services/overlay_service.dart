import 'package:flutter/services.dart';

import '../models/device_stats.dart';

/// Dart-side facade for the floating overlay window.
///
/// The overlay itself is a native `WindowManager` TYPE_APPLICATION_OVERLAY
/// window rendered by `OverlayService.kt`; this class just forwards calls.
class OverlayService {
  OverlayService._();
  static final OverlayService instance = OverlayService._();

  static const MethodChannel _channel = MethodChannel('com.zsdev.fpsmonitor/channel');

  /// Start/refresh the floating overlay (native side enforces the
  /// SYSTEM_ALERT_WINDOW permission and silently no-ops without it).
  Future<bool> startOverlay() async {
    try {
      return await _channel.invokeMethod<bool>('startOverlay') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> stopOverlay() async {
    try {
      return await _channel.invokeMethod<bool>('stopOverlay') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Push fresh stats into the overlay window (top-right corner).
  Future<void> updateOverlay(DeviceStats stats) async {
    try {
      await _channel.invokeMethod<bool>('updateOverlay', {
        'fps': stats.fps,
        'cpuTemp': stats.cpuTemp,
        'gpuTemp': stats.gpuTemp,
        'freeRamMb': stats.freeRamMb,
      });
    } on PlatformException {
      // Overlay may be gone (user revoked permission); ignore.
    }
  }
}
