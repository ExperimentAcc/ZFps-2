import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/device_info.dart';
import '../models/session.dart';
import '../services/export_service.dart';
import '../services/shizuku_service.dart';
import '../utils/csv_export.dart';
import '../utils/format_utils.dart';
import 'fps_graph.dart';

const Color _green = Color(0xFF4ADE80);
const Color _dim = Color(0xFF8B94A7);
const Color _text = Color(0xFFE5E7EB);
const Color _border = Color(0xFF232C3D);

/// Opens a preview of the report image with a Share button.
Future<void> showShareReportDialog(BuildContext context, Session session) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ShareReportDialog(session: session),
  );
}

class _ShareReportDialog extends StatefulWidget {
  final Session session;

  const _ShareReportDialog({required this.session});

  @override
  State<_ShareReportDialog> createState() => _ShareReportDialogState();
}

class _ShareReportDialogState extends State<_ShareReportDialog> {
  final GlobalKey _captureKey = GlobalKey();
  bool _busy = false;
  String? _error;

  Future<void> _share() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final boundary =
          _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode image');

      final ok = await ExportService.instance.shareBytes(
        data.buffer.asUint8List(),
        fileName: '${CsvExport.baseName(widget.session)}.png',
        mimeType: 'image/png',
        title: 'FPS report - ${widget.session.appName}',
      );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
      } else {
        setState(() => _error = 'Could not open the share sheet.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create the image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0D1117),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: _border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RepaintBoundary(
                  key: _captureKey,
                  child: SizedBox(
                    width: 360,
                    child: ReportShareCard(session: widget.session),
                  ),
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(_error!,
                  style: const TextStyle(color: Color(0xFFF87171), fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('Share image'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: const Color(0xFF0B1F12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The picture that gets shared: a branded summary of one session.
class ReportShareCard extends StatelessWidget {
  final Session session;

  const ReportShareCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final hasFrames = s.hasFrameData;

    final tiles = hasFrames
        ? [
            _Tile('AVG FPS', _fps(s.avgFps), fpsZoneColor(s.avgFps)),
            _Tile('1% LOW', _fps(s.onePercentLow), _zone(s.onePercentLow)),
            _Tile('0.1% LOW', _fps(s.pointOnePercentLow), _zone(s.pointOnePercentLow)),
          ]
        : [
            _Tile('AVG FPS', _fps(s.avgFps), fpsZoneColor(s.avgFps)),
            _Tile('MIN FPS', _fps(s.minFps), _zone(s.minFps > 0 ? s.minFps : null)),
            _Tile('MAX FPS', _fps(s.maxFps), const Color(0xFF60A5FA)),
          ];

    final stats = <(IconData, String, String)>[
      (Icons.thermostat_outlined, 'CPU temp', Fmt.temp(s.avgCpuTemp)),
      (Icons.thermostat_outlined, 'GPU temp', Fmt.temp(s.avgGpuTemp)),
      (Icons.memory_outlined, 'CPU usage', Fmt.percent(s.avgCpuUsage)),
      (Icons.grid_view_outlined, 'GPU usage', Fmt.percent(s.avgGpuUsage)),
      (Icons.storage_outlined, 'Free RAM', Fmt.mb(s.avgFreeRam)),
      (Icons.battery_6_bar_outlined, 'Battery drop', '${s.batteryDropPercent.toStringAsFixed(0)}%'),
      (Icons.bolt_outlined, 'Battery current', Fmt.currentMa(s.avgBatteryCurrentMa)),
      (Icons.power_outlined, 'Power draw', Fmt.watts(s.avgPowerWatts)),
    ];

    final fallbackDevice = ShizukuService.instance.cachedDeviceInfo;
    final deviceHeader = DeviceInfo.formatSummary(
      s.deviceModel ?? fallbackDevice?.deviceModel,
      s.socName ?? fallbackDevice?.socName,
      s.totalRamMb ?? fallbackDevice?.totalRamMb,
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16202F), Color(0xFF0B0F16)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand row
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0F16),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFF2A3548)),
                ),
                child: const Icon(Icons.speed_rounded, color: _green, size: 19),
              ),
              const SizedBox(width: 8),
              const Text('FPS Monitor',
                  style: TextStyle(
                      color: _text, fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            s.appName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: _text, fontSize: 23, fontWeight: FontWeight.w800, height: 1.1),
          ),
          const SizedBox(height: 4),
          Text(
            '${Fmt.dateTime(s.startTime)}  •  ${s.durationFormatted}',
            style: const TextStyle(color: _dim, fontSize: 12),
          ),
          if (deviceHeader.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF111826),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.smartphone_rounded, size: 14, color: _dim),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      deviceHeader,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB9C2D0),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Big numbers
          Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: tiles[i]),
              ],
            ],
          ),

          // Graph
          if (s.fpsSamples.where((e) => e >= 0).length >= 2) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              decoration: BoxDecoration(
                color: const Color(0xFF111826),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('FPS over time',
                      style: TextStyle(
                          color: _text, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  FpsGraph(fps: s.fpsSamples, lows: s.lows, interactive: false),
                ],
              ),
            ),
          ],

          // Other stats, two per row
          const SizedBox(height: 12),
          for (var i = 0; i < stats.length; i += 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: _StatItem(stats[i])),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < stats.length ? _StatItem(stats[i + 1]) : const SizedBox(),
                  ),
                ],
              ),
            ),
          if (hasFrames && s.avgFrameTimeMs != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _StatItem(
                (Icons.timer_outlined, 'Avg frame time',
                    '${s.avgFrameTimeMs!.toStringAsFixed(1)} ms'),
              ),
            ),

          const SizedBox(height: 12),
          const Divider(color: _border, height: 1),
          const SizedBox(height: 10),
          const Text(
            'Measured with FPS Monitor  •  github.com/zsdev07/ZFps',
            style: TextStyle(color: Color(0xFF5B6578), fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  static String _fps(double? v) => (v == null || v <= 0) ? '--' : v.toStringAsFixed(0);

  static Color _zone(double? v) => v == null ? _dim : fpsZoneColor(v);
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Tile(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111826),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: _dim, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final (IconData, String, String) item;

  const _StatItem(this.item);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(item.$1, size: 15, color: _dim),
        const SizedBox(width: 6),
        Expanded(
          child: Text(item.$2, style: const TextStyle(color: _dim, fontSize: 11.5)),
        ),
        Text(item.$3,
            style: const TextStyle(
                color: _text, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
