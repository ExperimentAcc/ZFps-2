import 'package:hive/hive.dart';

import '../models/session.dart';

/// Hive access layer for persisted monitoring sessions.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const String sessionBoxName = 'sessions';

  Box<Session> get _box => Hive.box<Session>(sessionBoxName);

  /// All sessions, newest first.
  List<Session> getSessions() {
    final sessions = _box.values.toList();
    sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
    return sessions;
  }

  Future<void> saveSession(Session session) => _box.put(session.id, session);

  Future<void> deleteSession(String id) => _box.delete(id);

  Future<void> clearAll() => _box.clear();

  int get count => _box.length;
}
