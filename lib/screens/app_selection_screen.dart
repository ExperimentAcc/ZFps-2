import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/installed_app.dart';
import '../services/shizuku_service.dart';

/// Searchable list of launchable apps; pops with the chosen [InstalledApp].
class AppSelectionScreen extends StatefulWidget {
  const AppSelectionScreen({super.key});

  @override
  State<AppSelectionScreen> createState() => _AppSelectionScreenState();
}

class _AppSelectionScreenState extends State<AppSelectionScreen> {
  late Future<List<InstalledApp>> _appsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _appsFuture = ShizukuService.instance.getInstalledApps();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<InstalledApp> _filter(List<InstalledApp> apps) {
    if (_query.isEmpty) return apps;
    return apps
        .where((a) =>
            a.name.toLowerCase().contains(_query) ||
            a.packageName.toLowerCase().contains(_query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: const Color(0xFFE5E7EB),
        elevation: 0,
        title: const Text('Select app to monitor',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Color(0xFFE5E7EB)),
              decoration: InputDecoration(
                hintText: 'Search games & apps…',
                hintStyle: const TextStyle(color: Color(0xFF6B7484)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8B94A7)),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Color(0xFF8B94A7)),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF161C27),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<InstalledApp>>(
              future: _appsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF4ADE80)),
                        SizedBox(height: 14),
                        Text('Loading installed apps…',
                            style: TextStyle(color: Color(0xFF8B94A7))),
                      ],
                    ),
                  );
                }
                final apps = _filter(snapshot.data ?? const <InstalledApp>[]);
                if (apps.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off,
                              size: 48, color: Color(0xFF3A4457)),
                          const SizedBox(height: 12),
                          Text(
                            _query.isEmpty
                                ? 'No launchable apps found.\n'
                                    'Check the apps are installed for this user.'
                                : 'No apps match "$_query"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF8B94A7)),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: apps.length,
                  separatorBuilder: (_, __) => const Divider(
                      height: 1, color: Color(0xFF1F2733), indent: 72),
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    return ListTile(
                      leading: _AppIcon(app: app),
                      title: Text(
                        app.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFE5E7EB),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        app.packageName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7484)),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: Color(0xFF4B5568)),
                      onTap: () => Navigator.of(context).pop(app),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final InstalledApp app;
  const _AppIcon({required this.app});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF1A2130),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.android, color: Color(0xFF4ADE80), size: 24),
    );
    if (app.icon.isEmpty) return fallback;
    try {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          Uint8List.fromList(app.icon),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    } catch (_) {
      return fallback;
    }
  }
}
