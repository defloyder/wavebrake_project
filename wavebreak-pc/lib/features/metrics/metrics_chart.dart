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
  // Scales down to 0.1 Mbps so even light traffic fills the chart with a
  // readable wave (axis labels stay honest).
  if (peak <= 0.1) return 0.1;
  final exp = math.pow(10, (math.log(peak) / math.ln10).floor()).toDouble();
  for (final m in const [1, 2, 5, 10]) {
    if (peak <= m * exp) return m * exp;
  }
  return 10 * exp;
}

/// Download (arctic) and upload (crimson) waves over [windowMs] ending at
/// [renderNowMs] (epoch ms, fractional — the caller advances it every
/// frame, ~1.5 s behind real time, so the line flows out continuously
/// instead of new samples popping in). The head is interpolated between
/// the two samples around [renderNowMs]. [maxMbps] comes from the caller
/// already eased, so the scale glides. Depth: translucent gradient fills,
/// faint inner contours fading towards the base, a few curved vertical
/// threads, a thin crest with soft bloom. [touchX] (0..1) draws a cursor.
class ThroughputChartPainter extends CustomPainter {
  ThroughputChartPainter({
    required this.samples,
    required this.windowMs,
    required this.renderNowMs,
    required this.maxMbps,
    required this.minutesLabel,
    this.unitMin = 'min',
    this.nowLabel = 'now',
    this.touchX,
    this.upColor = Ic.crimson,
  });

  final List<RateSample> samples;
  final double windowMs;
  final double renderNowMs;
  final double maxMbps;
  final int minutesLabel;

  /// Localized "min" and "now" for the time axis.
  final String unitMin;
  final String nowLabel;
  final double? touchX;

  /// Upload series: the flag accent (the brand color), like the rest.
  final Color upColor;

  static const _left = 34.0, _bottom = 22.0, _top = 8.0;

  /// Peak (Mbps) of the samples inside the window — the caller eases the
  /// axis towards niceMaxMbps(peak * 1.1).
  static double peakMbps(
      List<RateSample> samples, double renderNowMs, double windowMs) {
    final start = renderNowMs - windowMs;
    var peak = 0.0;
    for (final s in samples) {
      final t = s.at.millisecondsSinceEpoch.toDouble();
      if (t < start - 2000 || t > renderNowMs + 2000) continue;
      peak = math.max(peak, math.max(s.downBps, s.upBps) / 1e6);
    }
    return peak;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_left, _top, size.width, size.height - _bottom);
    final start = renderNowMs - windowMs;

    // Axis labels and faint grid.
    final grid = Paint()
      ..color = Ic.glassBorder.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = plot.bottom - plot.height * f;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _label(
          canvas, _fmtAxis(maxMbps * f), Offset(0, y - 7), 30, TextAlign.right);
    }
    _label(canvas, '−$minutesLabel $unitMin', Offset(plot.left, plot.bottom + 5), 60,
        TextAlign.left);
    _label(canvas, nowLabel, Offset(plot.right - 60, plot.bottom + 5), 60,
        TextAlign.right);

    // Samples up to the render time (one before the window so the line
    // enters from the left edge), plus an interpolated head at renderNow.
    final pts = <(double, double, double)>[]; // (t, down, up)
    RateSample? next;
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final t = s.at.millisecondsSinceEpoch.toDouble();
      if (t > renderNowMs) {
        next = s;
        break;
      }
      final keepPrev = i + 1 < samples.length &&
          samples[i + 1].at.millisecondsSinceEpoch >= start;
      if (t >= start || keepPrev) pts.add((t, s.downBps, s.upBps));
    }
    if (pts.isEmpty) return;
    final last = pts.last;
    if (next != null) {
      final tn = next.at.millisecondsSinceEpoch.toDouble();
      final k = ((renderNowMs - last.$1) / (tn - last.$1)).clamp(0.0, 1.0);
      final e = k * k * (3 - 2 * k); // smoothstep
      pts.add((
        renderNowMs,
        last.$2 + (next.downBps - last.$2) * e,
        last.$3 + (next.upBps - last.$3) * e,
      ));
    } else if (renderNowMs - last.$1 < 3000) {
      pts.add((renderNowMs, last.$2, last.$3));
    }
    if (pts.length < 2) return;

    Offset at(double t, double bps) => Offset(
          plot.left + plot.width * ((t - start) / windowMs),
          plot.bottom - plot.height * (bps / 1e6 / maxMbps).clamp(0.0, 1.0),
        );

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(plot.left, 0, plot.right, size.height));
    _series(
        canvas, plot, [for (final p in pts) at(p.$1, p.$2)], Ic.arctic, 1.0);
    _series(
        canvas, plot, [for (final p in pts) at(p.$1, p.$3)], upColor, 0.85);
    canvas.restore();

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

    // Depth: two receding ridges behind the wave (shifted up-right, fainter)
    // so it reads as a volume, not a flat line.
    for (final (dx, dy, a) in const [(10.0, -14.0, 0.10), (5.0, -7.0, 0.18)]) {
      final back = [
        for (final p in pts) Offset(p.dx + dx, p.dy + dy * _h(p, plot))
      ];
      final ridge = smoothPath(back);
      canvas.drawPath(
        Path.from(ridge)
          ..lineTo(back.last.dx, plot.bottom)
          ..lineTo(back.first.dx, plot.bottom)
          ..close(),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: a * strength),
              color.withValues(alpha: 0),
            ],
          ).createShader(plot),
      );
      canvas.drawPath(
        ridge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = color.withValues(alpha: a * 1.6 * strength),
      );
    }
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.42 * strength),
            color.withValues(alpha: 0.03),
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
      contour.color = color.withValues(alpha: 0.24 * (1 - k) * strength);
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

  static String _fmtAxis(double v) => v >= 10
      ? v.round().toString()
      : v == 0
          ? '0'
          : v >= 1
              ? v.toStringAsFixed(1)
              : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

  void _label(
      Canvas canvas, String text, Offset at, double width, TextAlign align) {
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
      old.windowMs != windowMs ||
      old.renderNowMs != renderNowMs ||
      old.maxMbps != maxMbps ||
      old.minutesLabel != minutesLabel ||
      old.unitMin != unitMin ||
      old.nowLabel != nowLabel ||
      old.touchX != touchX ||
      old.upColor != upColor;
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
      _dash(
          canvas,
          Offset(0, y),
          Offset(size.width, y),
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
              colors: [
                color.withValues(alpha: 0.22),
                color.withValues(alpha: 0)
              ],
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

/// A sparkline that morphs to new data (~0.8 s) instead of redrawing in a
/// jump when a sample is appended: the previous and new series are aligned
/// at their right ends and interpolated point by point.
class SmoothSpark extends StatefulWidget {
  const SmoothSpark({
    super.key,
    required this.values,
    required this.color,
    this.dashed = false,
    this.maxPoints = 40,
  });

  final List<double> values;
  final Color color;
  final bool dashed;
  final int maxPoints;

  @override
  State<SmoothSpark> createState() => _SmoothSparkState();
}

class _SmoothSparkState extends State<SmoothSpark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    value: 1,
  );
  List<double> _from = const [];
  List<double> _to = const [];

  List<double> _tail(List<double> v) =>
      v.length > widget.maxPoints ? v.sublist(v.length - widget.maxPoints) : v;

  @override
  void initState() {
    super.initState();
    _to = _tail(widget.values);
    _from = _to;
  }

  @override
  void didUpdateWidget(covariant SmoothSpark old) {
    super.didUpdateWidget(old);
    final next = _tail(widget.values);
    if (next.length == _to.length &&
        Iterable<int>.generate(next.length).every((i) => next[i] == _to[i])) {
      return;
    }
    _from = _current();
    _to = next;
    _anim.forward(from: 0);
  }

  /// The series as currently drawn (mid-animation included).
  List<double> _current() {
    final t = Curves.easeOutCubic.transform(_anim.value);
    if (_to.isEmpty) return _to;
    // Right-aligned: slot i on screen morphs from what was drawn there.
    final n = _to.length;
    return [
      for (var i = 0; i < n; i++)
        () {
          final j = _from.length - n + i;
          final old =
              _from.isEmpty ? _to[i] : _from[j.clamp(0, _from.length - 1)];
          return old + (_to[i] - old) * t;
        }(),
    ];
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => CustomPaint(
        painter: MiniWavePainter(_current(),
            color: widget.color, dashed: widget.dashed),
      ),
    );
  }
}

/// 0 at the base .. 1 at the top of the plot — ridges lift with the wave,
/// so a flat (idle) line doesn't float above the axis.
double _h(Offset p, Rect plot) =>
    ((plot.bottom - p.dy) / plot.height).clamp(0.0, 1.0);
