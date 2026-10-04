import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/vpn/live_metrics.dart';
import '../immersive/immersive_colors.dart';

/// Smooth path through [pts] (Catmull–Rom converted to cubic Béziers).
Path smoothPath(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = i == 0 ? pts[i] : pts[i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

/// "Nice" axis maximum in Mbps for the given peak: 1, 2, 5, 10, 20, 50 …
double niceMaxMbps(double peak) {
  if (peak <= 1) return 1;
  final exp = math.pow(10, (math.log(peak) / math.ln10).floor()).toDouble();
  for (final m in const [1, 2, 5, 10]) {
    if (peak <= m * exp) return m * exp;
  }
  return 10 * exp;
}

/// Download (arctic) and upload (crimson) waves over [window], measured
/// samples only. Depth: translucent gradient fills, faint inner contours
/// fading towards the base, a few curved vertical threads, a thin crest
/// with soft bloom. [touchX] (0..1) draws a cursor with both values.
class ThroughputChartPainter extends CustomPainter {
  ThroughputChartPainter({
    required this.samples,
    required this.window,
    required this.now,
    this.touchX,
  });

  final List<RateSample> samples;
  final Duration window;
  final DateTime now;
  final double? touchX;

  static const _left = 34.0, _bottom = 22.0, _top = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_left, _top, size.width, size.height - _bottom);
    final start = now.subtract(window);
    final visible = [for (final s in samples) if (s.at.isAfter(start)) s];
    var peak = 0.0;
    for (final s in visible) {
      peak = math.max(peak, math.max(s.downBps, s.upBps) / 1e6);
    }
    final maxMbps = niceMaxMbps(peak * 1.1);

    // Axis labels and faint grid.
    final grid = Paint()
      ..color = Ic.glassBorder.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = plot.bottom - plot.height * f;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _label(canvas, _fmtAxis(maxMbps * f), Offset(0, y - 7), 30, TextAlign.right);
    }
    final minutes = window.inMinutes;
    _label(canvas, '−$minutes мин', Offset(plot.left, plot.bottom + 5), 60,
        TextAlign.left);
    _label(canvas, 'сейчас', Offset(plot.right - 60, plot.bottom + 5), 60,
        TextAlign.right);

    if (visible.length < 2) return;

    Offset at(RateSample s, double bps) {
      final x = plot.left +
          plot.width *
              (s.at.difference(start).inMilliseconds / window.inMilliseconds);
      final y = plot.bottom - plot.height * (bps / 1e6 / maxMbps).clamp(0, 1);
      return Offset(x, y);
    }

    final down = [for (final s in visible) at(s, s.downBps)];
    final up = [for (final s in visible) at(s, s.upBps)];
    _series(canvas, plot, down, Ic.arctic, 1.0);
    _series(canvas, plot, up, Ic.crimson, 0.85);

    if (touchX != null) {
      final x = plot.left + plot.width * touchX!.clamp(0.0, 1.0);
      canvas.drawLine(
          Offset(x, plot.top),
          Offset(x, plot.bottom),
          Paint()
            ..color = Ic.text.withValues(alpha: 0.35)
            ..strokeWidth = 1);
    }
  }

  void _series(Canvas canvas, Rect plot, List<Offset> pts, Color color,
      double strength) {
    final crest = smoothPath(pts);
    final body = Path.from(crest)
      ..lineTo(pts.last.dx, plot.bottom)
      ..lineTo(pts.first.dx, plot.bottom)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.30 * strength),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(plot),
    );

    // Inner contours: the crest scaled towards the base, fading out.
    canvas.save();
    canvas.clipPath(body);
    final contour = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (var i = 1; i <= 10; i++) {
      final k = i / 11;
      final scaled = [
        for (final p in pts)
          Offset(p.dx, plot.bottom - (plot.bottom - p.dy) * (1 - k))
      ];
      contour.color = color.withValues(alpha: 0.16 * (1 - k) * strength);
      canvas.drawPath(smoothPath(scaled), contour);
    }
    // A few curved vertical threads.
    final thread = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = color.withValues(alpha: 0.10 * strength);
    for (var i = 1; i < pts.length - 1; i += math.max(1, pts.length ~/ 9)) {
      final p = pts[i];
      final path = Path()
        ..moveTo(p.dx, p.dy)
        ..quadraticBezierTo(
            p.dx + 6, (p.dy + plot.bottom) / 2, p.dx - 2, plot.bottom);
      canvas.drawPath(path, thread);
    }
    canvas.restore();

    canvas.drawPath(
      crest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = color.withValues(alpha: 0.12 * strength)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      crest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.95 * strength),
    );
  }

  static String _fmtAxis(double v) =>
      v >= 10 ? v.round().toString() : (v == 0 ? '0' : v.toStringAsFixed(1));

  void _label(Canvas canvas, String text, Offset at, double width,
      TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(color: Ic.textMuted, fontSize: 11)),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(ThroughputChartPainter old) =>
      old.samples != samples ||
      old.window != window ||
      old.now != now ||
      old.touchX != touchX;
}

/// Small sparkline for a quality card; [dashed] for packet loss.
class MiniWavePainter extends CustomPainter {
  MiniWavePainter(this.values, {required this.color, this.dashed = false});

  final List<double> values;
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      final y = size.height * 0.7;
      _dash(canvas, Offset(0, y), Offset(size.width, y),
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..strokeWidth = 1);
      return;
    }
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final span = math.max(maxV - minV, maxV * 0.25 + 1e-6);
    final pts = [
      for (var i = 0; i < values.length; i++)
        Offset(
          size.width * i / (values.length - 1),
          size.height * (0.85 - 0.7 * ((values[i] - minV) / span)),
        )
    ];
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.85);
    if (dashed) {
      for (var i = 0; i < pts.length - 1; i++) {
        _dash(canvas, pts[i], pts[i + 1], paint);
      }
    } else {
      final path = smoothPath(pts);
      canvas.drawPath(
          Path.from(path)
            ..lineTo(size.width, size.height)
            ..lineTo(0, size.height)
            ..close(),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
            ).createShader(Offset.zero & size));
      canvas.drawPath(path, paint);
    }
  }

  void _dash(Canvas canvas, Offset a, Offset b, Paint p) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    for (double s = 0; s < len; s += 6) {
      canvas.drawLine(a + dir * s, a + dir * math.min(s + 3, len), p);
    }
  }

  @override
  bool shouldRepaint(MiniWavePainter old) =>
      old.values != values || old.color != color || old.dashed != dashed;
}
