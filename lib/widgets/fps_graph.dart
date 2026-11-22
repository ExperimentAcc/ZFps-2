import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/format_utils.dart';

const Color _green = Color(0xFF4ADE80);
const Color _amber = Color(0xFFFBBF24);
const Color _red = Color(0xFFF87171);
const Color _violet = Color(0xFFA78BFA);
const Color _grid = Color(0xFF232C3D);
const Color _dim = Color(0xFF8B94A7);

/// 55+ green, 30-54 yellow, below 30 red (same colors as the overlay).
Color fpsZoneColor(double fps) {
  if (fps >= 55) return _green;
  if (fps >= 30) return _amber;
  return _red;
}

/// FPS-over-time graph with a 1% low line and an average line.
/// Tap or drag on it to inspect a point; double-tap to clear.
class FpsGraph extends StatefulWidget {
  /// FPS per poll.
  final List<double> fps;

  /// 1% low per poll (same length as [fps], negative = unknown). May be empty.
  final List<double> lows;

  /// Time between two samples.
  final Duration step;

  /// Tap / drag to inspect points. Turn off for static images.
  final bool interactive;

  const FpsGraph({
    super.key,
    required this.fps,
    required this.lows,
    this.step = const Duration(seconds: 2),
    this.interactive = true,
  });

  @override
  State<FpsGraph> createState() => _FpsGraphState();
}

class _FpsGraphState extends State<FpsGraph> {
  static const double _padL = 30, _padR = 6, _padT = 8, _padB = 20;

  int? _selected;

  bool get _hasLows =>
      widget.lows.length == widget.fps.length && widget.lows.any((e) => e >= 0);

  double get _avg {
    final v = widget.fps.where((e) => e >= 0).toList();
    if (v.isEmpty) return 0;
    return v.reduce((a, b) => a + b) / v.length;
  }

  double get _yMax {
    var m = 0.0;
    for (final v in widget.fps) {
      if (v > m) m = v;
    }
    final top = math.max(30.0, (m * 1.08 / 10).ceil() * 10.0);
    return top;
  }

  void _select(double dx, double width) {
    final n = widget.fps.length;
    if (n < 2) return;
    final plotW = width - _padL - _padR;
    final t = math.min(1.0, math.max(0.0, (dx - _padL) / plotW));
    setState(() => _selected = (t * (n - 1)).round());
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.fps.length;
    if (n < 2) return const SizedBox.shrink();

    final sel = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 22, child: sel == null ? _legend() : _readout(sel)),
        const SizedBox(height: 6),
        SizedBox(
          height: 170,
          child: LayoutBuilder(
            builder: (context, c) {
              final graph = CustomPaint(
                size: Size(c.maxWidth, 170),
                painter: _GraphPainter(
                  fps: widget.fps,
                  lows: _hasLows ? widget.lows : const [],
                  avg: _avg,
                  yMax: _yMax,
                  selected: sel,
                  totalTime: widget.step * (n - 1),
                ),
              );
              if (!widget.interactive) return graph;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _select(d.localPosition.dx, c.maxWidth),
                onHorizontalDragStart: (d) => _select(d.localPosition.dx, c.maxWidth),
                onHorizontalDragUpdate: (d) => _select(d.localPosition.dx, c.maxWidth),
                onDoubleTap: () => setState(() => _selected = null),
                child: graph,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _legend() {
    Widget dot(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(t, style: const TextStyle(color: _dim, fontSize: 11)),
          ],
        );
    return Row(
      children: [
        dot(_green, 'FPS'),
        if (_hasLows) ...[const SizedBox(width: 12), dot(_violet, '1% low')],
        const SizedBox(width: 12),
        dot(Colors.white54, 'avg ${_avg.toStringAsFixed(0)}'),
        if (widget.interactive) ...const [
          Spacer(),
          Text('tap to inspect', style: TextStyle(color: Color(0xFF4B5568), fontSize: 10)),
        ],
      ],
    );
  }

  Widget _readout(int i) {
    final fps = widget.fps[i];
    final low = _hasLows ? widget.lows[i] : -1.0;
    final t = Fmt.durationHms(widget.step * i);
    return Row(
      children: [
        Text(t, style: const TextStyle(color: _dim, fontSize: 11.5)),
        const SizedBox(width: 12),
        Text('${fps.toStringAsFixed(0)} FPS',
            style: TextStyle(
                color: fpsZoneColor(fps), fontSize: 12.5, fontWeight: FontWeight.w800)),
        if (low >= 0) ...[
          const SizedBox(width: 12),
          Text('1% low ${low.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: _violet, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ],
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<double> fps;
  final List<double> lows;
  final double avg;
  final double yMax;
  final int? selected;
  final Duration totalTime;

  _GraphPainter({
    required this.fps,
    required this.lows,
    required this.avg,
    required this.yMax,
    required this.selected,
    required this.totalTime,
  });

  static const double _l = 30, _r = 6, _t = 8, _b = 20;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_l, _t, size.width - _r, size.height - _b);
    final n = fps.length;

    double yOf(double v) =>
        plot.bottom - plot.height * math.min(1.0, math.max(0.0, v / yMax));
    double xOf(int i) => plot.left + plot.width * (n <= 1 ? 0 : i / (n - 1));

    // Grid + y labels
    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _text(canvas, (yMax * i / 4).round().toString(), Offset(plot.left - 5, y),
          alignRight: true, size: 9.5);
    }

    // Time labels
    _text(canvas, '0:00', Offset(plot.left, plot.bottom + 4), size: 9.5, top: true);
    _text(canvas, Fmt.durationHms(totalTime), Offset(plot.right, plot.bottom + 4),
        alignRight: true, size: 9.5, top: true);
    if (n > 8) {
      _text(canvas, Fmt.durationHms(totalTime ~/ 2),
          Offset(plot.left + plot.width / 2, plot.bottom + 4),
          center: true, size: 9.5, top: true);
    }

    // Area under the FPS line
    final area = Path()..moveTo(xOf(0), plot.bottom);
    for (var i = 0; i < n; i++) {
      area.lineTo(xOf(i), yOf(math.max(0, fps[i])));
    }
    area
      ..lineTo(xOf(n - 1), plot.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_green.withOpacity(0.26), _green.withOpacity(0.0)],
        ).createShader(plot),
    );

    // Average line (dashed)
    if (avg > 0) {
      final y = yOf(avg);
      _dashed(canvas, Offset(plot.left, y), Offset(plot.right, y),
          Paint()
            ..color = Colors.white54
            ..strokeWidth = 1);
    }

    // 1% low line
    if (lows.isNotEmpty) {
      final p = Paint()
        ..color = _violet
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var i = 1; i < n; i++) {
        if (lows[i] < 0 || lows[i - 1] < 0) continue;
        canvas.drawLine(Offset(xOf(i - 1), yOf(lows[i - 1])), Offset(xOf(i), yOf(lows[i])), p);
      }
    }

    // FPS line, colored by zone
    final line = Paint()
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < n; i++) {
      line.color = fpsZoneColor((fps[i] + fps[i - 1]) / 2);
      canvas.drawLine(Offset(xOf(i - 1), yOf(fps[i - 1])), Offset(xOf(i), yOf(fps[i])), line);
    }

    // Selection marker
    final s = selected;
    if (s != null && s >= 0 && s < n) {
      final x = xOf(s);
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = Colors.white30
          ..strokeWidth = 1,
      );
      canvas.drawCircle(Offset(x, yOf(fps[s])), 4.5, Paint()..color = fpsZoneColor(fps[s]));
      canvas.drawCircle(
        Offset(x, yOf(fps[s])),
        4.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      if (lows.isNotEmpty && lows[s] >= 0) {
        canvas.drawCircle(Offset(x, yOf(lows[s])), 3.5, Paint()..color = _violet);
      }
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0, gap = 4.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d += dash + gap;
    }
  }

  void _text(Canvas canvas, String text, Offset at,
      {bool alignRight = false, bool center = false, bool top = false, double size = 10}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: _dim, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (alignRight) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    final dy = top ? at.dy : at.dy - tp.height / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) =>
      old.selected != selected ||
      old.fps != fps ||
      old.lows != lows ||
      old.avg != avg ||
      old.yMax != yMax;
}
