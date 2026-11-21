import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/session.dart';

/// Local notifications: session-complete alert and channel management.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String sessionChannelId = 'session_channel';
  static const String sessionChannelName = 'Session alerts';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_fps');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    const channel = AndroidNotificationChannel(
      sessionChannelId,
      sessionChannelName,
      description: 'Notifies when a monitoring session has finished',
      importance: Importance.high,
    );
    await android?.createNotificationChannel(channel);

    // Android 13+ runtime permission
    await android?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Fired once when a monitoring session stops.
  Future<void> showSessionComplete(Session session) async {
    if (!_initialized) await init();

    final avgFps = session.avgFps > 0 ? session.avgFps.toStringAsFixed(0) : '--';
    final body = '${session.appName} • avg $avgFps FPS • ${session.durationFormatted}'
        ' • battery −${session.batteryDropPercent.toStringAsFixed(0)}%';

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        sessionChannelId,
        sessionChannelName,
        channelDescription: 'Notifies when a monitoring session has finished',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_fps',
        category: AndroidNotificationCategory.status,
      ),
    );

    try {
      await _plugin.show(
        session.hashCode & 0x7fffffff,
        'Session complete',
        body,
        details,
        payload: session.id,
      );
    } catch (_) {
      // Notifications are best-effort; never crash teardown over this.
    }
  }
}
