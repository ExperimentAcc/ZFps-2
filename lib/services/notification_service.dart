import '../models/session.dart';

/// Local notifications: session-complete alert and channel management.
///
/// Stub implementation — flutter_local_notifications was removed because its
/// compileSdk 35 requirement is incompatible with the Android Gradle Plugin
/// version required by Flutter's Gradle plugin on this toolchain.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String sessionChannelId = 'session_channel';
  static const String sessionChannelName = 'Session alerts';

  bool _initialized = false;

  Future<void> init() async {
    _initialized = true;
  }

  /// Fired once when a monitoring session stops (no-op in stub build).
  Future<void> showSessionComplete(Session session) async {
    if (!_initialized) await init();
    // Notifications are best-effort; stub does nothing.
  }
}
