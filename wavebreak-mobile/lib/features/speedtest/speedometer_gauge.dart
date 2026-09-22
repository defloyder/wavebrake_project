import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/wb_colors.dart';

/// A half-circle (speedometer-style) gauge — arc sweeps left-to-right
/// proportional to [valueMbps] against [maxMbps]. Animates smoothly
/// between successive live readings via an implicit [TweenAnimationBuilder]
/// rather than jumping frame-to-frame — SpeedTestService's own sample
/// throttling (a few times a second) already keeps updates infrequent
/// enough that without this the needle would visibly tick rather than
/// sweep.
class SpeedometerGauge extends StatelessWidget {
  const SpeedometerGauge({
    super.key,
    required this.valueMbps,
    required this.maxMbps,
    required this.label,
    required this.unit,
  });

  final double valueMbps;
  final double maxMbps;
  final String label;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final target = (valueMbps / maxMbps).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      // Matches SpeedTestService's own ~200ms sample throttle — a
      // same-length animation between samples reads as one continuous
      // sweep instead of either lagging behind or visibly settling
      // before the next sample arrives.
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, animatedFraction, child) {
        return CustomPaint(
          painter: _GaugePainter(fraction: animatedFraction),
          child: child,
        );
      },
      child: Padding(
        // Pushes the numeral/unit down into the lower half of the
        // gauge's bounding box, clear of the arc itself (drawn only in
        // the upper half).
        padding: const EdgeInsets.only(top: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Text(
                valueMbps.toStringAsFixed(valueMbps >= 100 ? 0 : 1),
                key: ValueKey(valueMbps.toStringAsFixed(1)),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: WbColors.ice,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              unit,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: WbColors.ice60,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: WbColors.waveCyan,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.fraction});

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    // A half-circle spanning the top half of [size] — center at the
    // horizontal midpoint, vertically at the bottom edge so the arc
    // bows upward into the available space (a full circle's worth of
    // radius would clip; the bottom half is simply never drawn).
    final center = Offset(size.width / 2, size.height * 0.62);
    final radius = math.min(size.width / 2, size.height * 0.62) - 14;
    const startAngle = math.pi; // 180°, i.e. pointing left
    const sweepAngle = math.pi; // half circle, ending pointing right

    final track = Paint()
      ..color = WbColors.ice08
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      track,
    );

    if (fraction <= 0) return;
    final progress = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: const [WbColors.oceanTeal, WbColors.waveCyan],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * fraction,
      false,
      progress,
    );

    // A small needle-tip dot at the current position — reads more like a
    // live instrument than the arc's rounded end-cap alone does,
    // especially at low fractions where the arc itself is barely visible.
    final tipAngle = startAngle + sweepAngle * fraction;
    final tip = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );
    canvas.drawCircle(
      tip,
      7,
      Paint()..color = WbColors.ice,
    );
    canvas.drawCircle(
      tip,
      7,
      Paint()
        ..color = WbColors.waveCyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}
