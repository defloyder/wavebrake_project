import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/wb_colors.dart';
import '../immersive/immersive_colors.dart';
import 'wave_meter.dart' show WaveMeterVisualState;

/// The speed test's dial in the app's own look (owner, 13.10: the square
/// porthole didn't match the new design): a glowing glass orb with the
/// reading — the same orb the settings pages carry — inside a 240° scale
/// that fills in the location's accent, with slow ripples going out while
/// a test runs.
///
/// The scale is square-root, like a car's speedometer reads: 1, 10 and
/// 100 Mbps all get room instead of everything piling up near zero.
class SpeedGauge extends StatefulWidget {
  const SpeedGauge({
    super.key,
    required this.visualState,
    required this.valueMbps,
    required this.maxMbps,
    required this.unit,
    required this.label,
    required this.accent,
  });

  final WaveMeterVisualState visualState;
  final double valueMbps;
  final double maxMbps;
  final String unit;

  /// What is being measured now (or "Test complete").
  final String label;
  final Color accent;

  @override
  State<SpeedGauge> createState() => _SpeedGaugeState();
}

class _SpeedGaugeState extends State<SpeedGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200));

  bool get _running => widget.visualState == WaveMeterVisualState.running;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRipple();
  }

  @override
  void didUpdateWidget(SpeedGauge old) {
    super.didUpdateWidget(old);
    if (old.visualState != widget.visualState) _syncRipple();
  }

  void _syncRipple() {
    if (_running && !MediaQuery.disableAnimationsOf(context)) {
      if (!_ripple.isAnimating) _ripple.repeat();
    } else {
      _ripple
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failed = widget.visualState == WaveMeterVisualState.failed;
    final done = widget.visualState == WaveMeterVisualState.done;
    final color = failed ? WbColors.error : widget.accent;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return LayoutBuilder(builder: (context, box) {
      // As wide as it may be, unless that is taller than the room.
      final w = math.min(box.maxWidth, box.maxHeight / _Geo.aspect);
      final geo = _Geo(w);
      return Center(
        child: SizedBox(
          width: w,
          height: w * _Geo.aspect,
          child: TweenAnimationBuilder<double>(
            tween:
                Tween(end: (widget.valueMbps / widget.maxMbps).clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, fraction, _) => Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _GaugePainter(
                        fraction: math.sqrt(fraction),
                        color: color,
                        ripple: _ripple,
                        maxMbps: widget.maxMbps,
                        geo: geo,
                        labelStyle: labelStyle,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: geo.center.dx - geo.orb / 2,
                  top: geo.center.dy - geo.orb / 2,
                  child: _Core(
                    size: geo.orb,
                    color: color,
                    value: _reading(),
                    unit: widget.unit,
                    label: widget.label,
                    done: done,
                    failed: failed,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  String _reading() {
    if (widget.visualState == WaveMeterVisualState.idle ||
        widget.visualState == WaveMeterVisualState.failed) {
      return '–';
    }
    final v = widget.valueMbps;
    return v.toStringAsFixed(v >= 100 ? 0 : 1);
  }
}

/// The orb in the middle: the number, its unit and the phase.
class _Core extends StatelessWidget {
  const _Core({
    required this.size,
    required this.color,
    required this.value,
    required this.unit,
    required this.label,
    required this.done,
    required this.failed,
  });

  final double size;
  final Color color;
  final String value;
  final String unit;
  final String label;
  final bool done;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0.05),
        ]),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.22),
              blurRadius: size * 0.3,
              spreadRadius: 1),
        ],
      ),
      padding: EdgeInsets.all(size * 0.12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (done || failed)
              Icon(done ? Icons.check_rounded : Icons.close_rounded,
                  size: 22, color: color),
            Text(
              value,
              style: const TextStyle(
                color: Ic.text,
                fontSize: 46,
                height: 1.05,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(unit,
                style: const TextStyle(
                    color: Ic.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: failed ? WbColors.error : Ic.textMuted,
                    fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.color,
    required this.ripple,
    required this.maxMbps,
    required this.geo,
    this.labelStyle,
  }) : super(repaint: ripple);

  final _Geo geo;
  final TextStyle? labelStyle;

  /// 0..1 along the scale (already square-root mapped).
  final double fraction;
  final Color color;
  final Animation<double> ripple;
  final double maxMbps;

  static const _start = math.pi * 5 / 6; // 150°
  static const _sweep = math.pi * 4 / 3; // 240°

  @override
  void paint(Canvas canvas, Size size) {
    final c = geo.center;
    final r = geo.radius;
    final stroke = geo.stroke;

    // Ripples out of the orb while measuring.
    if (ripple.isAnimating) {
      final inner = geo.orb / 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (var i = 0; i < 3; i++) {
        final p = (ripple.value + i / 3) % 1;
        paint.color = color.withValues(alpha: 0.30 * (1 - p));
        canvas.drawCircle(c,
            inner + (r - stroke - inner) * Curves.easeOut.transform(p), paint);
      }
    }

    final rect = Rect.fromCircle(center: c, radius: r);
    // Track.
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = Ic.text.withValues(alpha: 0.07),
    );

    // Ticks and a few figures along the inside.
    final tick = Paint()
      ..strokeWidth = 1
      ..color = Ic.text.withValues(alpha: 0.18);
    for (var i = 0; i <= 24; i++) {
      final a = _start + _sweep * i / 24;
      final major = i % 6 == 0;
      final r1 = r - stroke * 1.4;
      final r2 = r1 - (major ? stroke * 0.9 : stroke * 0.45);
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r1,
          c + Offset(math.cos(a), math.sin(a)) * r2, tick);
    }
    for (final mbps in [0, 10, 50, 100, maxMbps.round()]) {
      final a = _start + _sweep * math.sqrt(mbps / maxMbps);
      final tp = TextPainter(
        text: TextSpan(
            text: '$mbps',
            style: (labelStyle ?? const TextStyle()).copyWith(
                color: Ic.textMuted.withValues(alpha: 0.8),
                fontSize: geo.width * 0.032)),
        textDirection: TextDirection.ltr,
      )..layout();
      final at = c + Offset(math.cos(a), math.sin(a)) * (r + stroke * 2.1);
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    if (fraction <= 0) return;
    final sweep = _sweep * fraction;
    // Glow under the value arc, then the arc itself.
    canvas.drawArc(
      rect,
      _start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 1.6
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke),
    );
    canvas.drawArc(
      rect,
      _start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          endAngle: _sweep,
          colors: [color.withValues(alpha: 0.35), color],
          transform: const GradientRotation(_start),
        ).createShader(rect),
    );
    // The tip.
    final a = _start + sweep;
    final tip = c + Offset(math.cos(a), math.sin(a)) * r;
    canvas.drawCircle(
        tip, stroke * 0.95, Paint()..color = color.withValues(alpha: 0.35));
    canvas.drawCircle(tip, stroke * 0.5, Paint()..color = Ic.text);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.color != color || old.maxMbps != maxMbps;
}

/// Where things go for a gauge [width] wide: the 240° arc leaves its
/// bottom quarter open, so the box is shorter than it is wide — no empty
/// band under the dial.
class _Geo {
  _Geo(this.width);

  final double width;

  /// Height / width.
  static const aspect = 0.76;

  double get radius => width * 0.40;
  double get stroke => width * 0.032;
  double get orb => width * 0.46;

  /// Room above the arc for the figures and the glow.
  Offset get center => Offset(width / 2, width * 0.09 + radius);
}
