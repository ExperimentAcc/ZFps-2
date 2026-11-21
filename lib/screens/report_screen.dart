import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../models/session.dart';
import '../utils/format_utils.dart';
import '../widgets/stat_card.dart';

/// History of saved sessions with expandable per-session stats.
class ReportScreen extends StatefulWidget {
  /// When set, the session with this id is expanded and highlighted on open.
  final String? focusSessionId;

  const ReportScreen({super.key, this.focusSessionId});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late List<Session> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = AppDatabase.instance.getSessions();
  }

  void _reload() {
    setState(() => _sessions = AppDatabase.instance.getSessions());
  }

  Future<void> _deleteSession(Session session) async {
    await AppDatabase.instance.deleteSession(session.id);
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted session for ${session.appName}'),
        backgroundColor: const Color(0xFF1F2733),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161C27),
        title: const Text('Clear all sessions?',
            style: TextStyle(color: Color(0xFFE5E7EB))),
        content: const Text(
          'This permanently deletes every saved performance report.',
          style: TextStyle(color: Color(0xFF8B94A7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B94A7))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all', style: TextStyle(color: Color(0xFFF87171))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AppDatabase.instance.clearAll();
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: const Color(0xFFE5E7EB),
        elevation: 0,
        title: const Text('Performance reports', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_sessions.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _sessions.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              color: const Color(0xFF4ADE80),
              onRefresh: () async => _reload(),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _sessions.length,
                itemBuilder: (context, index) => _SessionCard(
                  session: _sessions[index],
                  initiallyExpanded: _sessions[index].id == widget.focusSessionId,
                  onDelete: () => _deleteSession(_sessions[index]),
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFF161C27),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.insights_rounded,
                  size: 44, color: Color(0xFF3A4457)),
            ),
            const SizedBox(height: 18),
            const Text(
              'No sessions yet',
              style: TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Start monitoring a game and your FPS, temperatures,\n'
              'usage and battery reports will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8B94A7), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final Session session;
  final bool initiallyExpanded;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.session,
    required this.initiallyExpanded,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final fpsColor = session.avgFps >= 50
        ? const Color(0xFF4ADE80)
        : session.avgFps >= 30
            ? const Color(0xFFFBBF24)
            : const Color(0xFFF87171);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161C27),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232C3D)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Keep the ExpansionTile divider invisible for a cleaner card
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: const Color(0xFF8B94A7),
          collapsedIconColor: const Color(0xFF8B94A7),
          title: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: fpsColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Text(
                  session.avgFps > 0 ? session.avgFps.toStringAsFixed(0) : '--',
                  style: TextStyle(
                    color: fpsColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE5E7EB),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${Fmt.dateTime(session.startTime)} • ${session.durationFormatted}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8B94A7)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete session',
                icon: const Icon(Icons.delete_outline, color: Color(0xFF6B7484)),
                onPressed: onDelete,
              ),
            ],
          ),
          children: [
            const Divider(color: Color(0xFF232C3D), height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Avg FPS',
                    value: session.avgFps > 0 ? session.avgFps.toStringAsFixed(0) : '--',
                    accent: fpsColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStat(
                    label: 'Max FPS',
                    value: session.maxFps > 0 ? session.maxFps.toStringAsFixed(0) : '--',
                    accent: const Color(0xFF60A5FA),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStat(
                    label: 'Samples',
                    value: '${session.sampleCount}',
                    accent: const Color(0xFFA78BFA),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _StatLine(
              icon: Icons.battery_6_bar_outlined,
              label: 'Battery drop',
              value: '${session.batteryDropPercent.toStringAsFixed(0)}%',
              accent: const Color(0xFFFBBF24),
            ),
            _StatLine(
              icon: Icons.memory_outlined,
              label: 'CPU usage (avg / max)',
              value: '${Fmt.percent(session.avgCpuUsage)} / ${Fmt.percent(session.maxCpuUsage)}',
              accent: const Color(0xFF60A5FA),
            ),
            _StatLine(
              icon: Icons.grid_view_outlined,
              label: 'GPU usage (avg / max)',
              value: '${Fmt.percent(session.avgGpuUsage)} / ${Fmt.percent(session.maxGpuUsage)}',
              accent: const Color(0xFFA78BFA),
            ),
            _StatLine(
              icon: Icons.thermostat_outlined,
              label: 'CPU temperature (avg)',
              value: Fmt.temp(session.avgCpuTemp),
              accent: const Color(0xFFF87171),
            ),
            _StatLine(
              icon: Icons.thermostat_outlined,
              label: 'GPU temperature (avg)',
              value: Fmt.temp(session.avgGpuTemp),
              accent: const Color(0xFFFB923C),
            ),
            _StatLine(
              icon: Icons.sd_storage_outlined,
              label: 'Storage speed (avg)',
              value: Fmt.speed(session.avgStorageSpeed),
              accent: const Color(0xFF34D399),
            ),
            _StatLine(
              icon: Icons.storage_outlined,
              label: 'Free RAM (avg)',
              value: Fmt.mb(session.avgFreeRam),
              accent: const Color(0xFF4ADE80),
            ),
            _StatLine(
              icon: Icons.schedule_outlined,
              label: 'Duration',
              value: session.durationFormatted,
              accent: const Color(0xFF8B94A7),
            ),
            const SizedBox(height: 6),
            Text(
              session.packageName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xFF4B5568)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _MiniStat({required this.label, required this.value, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2130),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF232C3D)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8B94A7)),
          ),
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const _StatLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 17, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFB9C2D0)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFFE5E7EB),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
