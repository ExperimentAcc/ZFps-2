/// An installed launchable app that can be monitored.
class InstalledApp {
  final String name;
  final String packageName;

  /// PNG-encoded app icon (may be empty when unavailable).
  final List<int> icon;

  const InstalledApp({
    required this.name,
    required this.packageName,
    required this.icon,
  });

  factory InstalledApp.fromMap(Map<dynamic, dynamic> map) {
    final rawIcon = map['icon'];
    return InstalledApp(
      name: (map['name'] ?? 'Unknown') as String,
      packageName: (map['packageName'] ?? '') as String,
      icon: rawIcon is List<int> ? rawIcon : (rawIcon as List?)?.cast<int>() ?? const [],
    );
  }
}
