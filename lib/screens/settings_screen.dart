import 'package:flutter/material.dart';

import '../models/device_info.dart';
import '../services/monitor_service.dart';
import '../services/shizuku_service.dart';

const Color _bg = Color(0xFF0D1117);
const Color _card = Color(0xFF161C27);
const Color _border = Color(0xFF232C3D);
const Color _green = Color(0xFF4ADE80);
const Color _blue = Color(0xFF60A5FA);
const Color _amber = Color(0xFFFBBF24);
const Color _text = Color(0xFFE5E7EB);
const Color _textDim = Color(0xFF8B94A7);

/// App-wide monitoring & filtering preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  DeviceInfo? _deviceInfo;

  @override
  void initState() {
    super.initState();
    _deviceInfo = ShizukuService.instance.cachedDeviceInfo;
    _refreshDeviceInfo();
  }

  Future<void> _refreshDeviceInfo() async {
    final info = await ShizukuService.instance.getDeviceInfo(refresh: true);
    if (!mounted || info == null) return;
    setState(() => _deviceInfo = info);
  }

  @override
  Widget build(BuildContext context) {
    final monitor = MonitorService.instance;
    final info = _deviceInfo;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _text,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800, color: _text),
        ),
      ),
      body: ListenableBuilder(
        listenable: monitor,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              _section(
                'FPS & Spike Filtering',
                [
                  _switchTile(
                    icon: Icons.filter_alt_outlined,
                    accent: _blue,
                    title: 'Exclude loading screens',
                    subtitle:
                        'Filter 0 FPS, < 5 FPS windows & > 500 ms stalls from 1% / 0.1% lows',
                    value: monitor.excludeLoadingScreens,
                    onChanged: (v) => monitor.setExcludeLoadingScreens(v),
                  ),
                  const Divider(color: _border, height: 1, indent: 16, endIndent: 16),
                  _switchTile(
                    icon: Icons.auto_fix_high_outlined,
                    accent: _amber,
                    title: 'Exclude < 10 FPS spikes',
                    subtitle:
                        'Filter < 10 FPS transition spikes (e.g. map downloads, TDM round reloads)',
                    value: monitor.excludeSub10Fps,
                    onChanged: (v) => monitor.setExcludeSub10Fps(v),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _section(
                'Device Metadata Header',
                [
                  _infoRow('Device model', info?.deviceModel ?? '--'),
                  const Divider(color: _border, height: 1, indent: 16, endIndent: 16),
                  _infoRow('Chipset (SoC)', info?.socName ?? '--'),
                  const Divider(color: _border, height: 1, indent: 16, endIndent: 16),
                  _infoRow(
                    'Total RAM',
                    info != null && info.totalRamMb > 0
                        ? info.ramDetailed
                        : '--',
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(6, 14, 6, 0),
                child: Text(
                  'Tip: Leading and trailing loading screens are auto-trimmed when a session ends. '
                  'You can also trim the start or end of any recorded timeline with the slider inside Performance reports.',
                  style: TextStyle(color: _textDim, fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              title,
              style: const TextStyle(
                color: _textDim,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _textDim,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            activeColor: _green,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _textDim, fontSize: 13),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
