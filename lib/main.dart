import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'database/app_database.dart';
import 'models/session.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Hive + persistence
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(SessionAdapter());
  }
  await Hive.openBox<Session>(AppDatabase.sessionBoxName);

  // Local notifications (creates channel, asks POST_NOTIFICATIONS on 13+)
  await NotificationService.instance.init();

  runApp(const FpsMonitorApp());
}

class FpsMonitorApp extends StatelessWidget {
  const FpsMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0D1117);
    const scheme = ColorScheme.dark(
      primary: Color(0xFF4ADE80),
      onPrimary: Color(0xFF06280F),
      surface: Color(0xFF161C27),
      onSurface: Color(0xFFE5E7EB),
      error: Color(0xFFF87171),
    );

    return MaterialApp(
      title: 'FPS Monitor',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: scheme,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          surfaceTintColor: Colors.transparent,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1F2733),
          contentTextStyle: const TextStyle(color: Color(0xFFE5E7EB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dividerColor: const Color(0xFF232C3D),
        cardTheme: CardTheme(
          color: const Color(0xFF161C27),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
