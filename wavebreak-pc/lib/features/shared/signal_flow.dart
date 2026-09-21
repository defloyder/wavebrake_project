import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/wb_colors.dart';

/// A handful of soft, glowing light streaks rising through a narrow panel —
/// stands in for encrypted traffic moving through the tunnel. Used in the
/// side rail instead of [AnimatedWaves]: that panel is far too narrow and
/// tall for a horizontal wave to ever read as "the same shape" as the wide
/// ocean background behind Home, no matter how well their timing is
/// synced, so a motif built for a vertical strip fits better than trying
/// to force the wave to match.
class SignalFlow extends StatefulWidget {
  const SignalFlow({
    super.key,
    this.tint,
    this.speed = 1.0,
    this.streakCount = 6,
    this.opacity = 1.0,
  });

  final Color? tint;
  final double speed;
  final int streakCount;
  final double opacity;

  @override
  State<SignalFlow> createState() => _SignalFlowState();
}

const _flowPeriod = Duration(seconds: 10);

class _SignalFlowState extends State<SignalFlow> with SingleTickerProviderStateMixin {
  // Ticks every frame purely to trigger rebuilds; the real phase comes from
  // the wall clock (below) so every instance of this widget on screen stays
  // in lockstep regardless of when it happened to mount.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _flowPeriod,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.tint ?? WbColors.waveCyan;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Raw, never-wrapped elapsed time. Wrapping to a [0,1) progress
          // fraction *before* multiplying by `speed` — the previous
          // approach — makes every streak snap to a new position in
          // lockstep every `_flowPeriod`, because at any speed other than
          // a whole number that wrap lands somewhere other than where the
          // streak had actually reached. Feeding raw time straight into
          // each streak's own modulo (applied once, after `speed`) means
          // the only wrap left is each streak's individual loop — which by
          // construction always happens off-screen, so it's invisible.
          final nowSeconds = DateTime.now().millisecondsSinceEpoch / 1000;
          return CustomPaint(
            painter: _SignalPainter(
              time: nowSeconds,
              periodSeconds: _flowPeriod.inMilliseconds / 1000,
              tint: tint,
              speed: widget.speed.clamp(0.4, 2.6),
              streakCount: widget.streakCount,
              opacity: widget.opacity,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _SignalPainter extends CustomPainter {
  const _SignalPainter({
    required this.time,
    required this.periodSeconds,
    required this.tint,
    required this.speed,
    required this.streakCount,
    required this.opacity,
  });

  final double time;
  final double periodSeconds;
  final Color tint;
  final double speed;
  final int streakCount;
  final double opacity;

  // Fixed layout so streaks don't reshuffle frame to frame — only their
  // position along the loop moves. Width is relative to the panel's own
  // width, so it scales sensibly whether the rail is collapsed or expanded.
  static const _specs = [
    (x: 0.22, len: 0.30, cycles: 1.00, phase: 0.00, alpha: 0.38, width: 1.5),
    (x: 0.52, len: 0.20, cycles: 0.82, phase: 0.35, alpha: 0.28, width: 1.2),
    (x: 0.74, len: 0.36, cycles: 1.15, phase: 0.62, alpha: 0.34, width: 1.6),
    (x: 0.86, len: 0.18, cycles: 0.90, phase: 0.18, alpha: 0.24, width: 1.1),
    (x: 0.36, len: 0.26, cycles: 1.05, phase: 0.80, alpha: 0.22, width: 1.3),
    (x: 0.62, len: 0.16, cycles: 0.95, phase: 0.50, alpha: 0.18, width: 1.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final specs = _specs.take(streakCount.clamp(1, _specs.length));
    for (final spec in specs) {
      _streak(
        canvas,
        size,
        x: spec.x,
        lengthFraction: spec.len,
        cycles: spec.cycles,
        phase: spec.phase,
        alpha: spec.alpha * opacity,
        width: spec.width,
      );
    }
  }

  void _streak(
    Canvas canvas,
    Size size, {
    required double x,
    required double lengthFraction,
    required double cycles,
    required double phase,
    required double alpha,
    required double width,
  }) {
    if (alpha <= 0) return;
    // Each streak can loop at its own rate (`cycles`) and offset (`phase`)
    // so they drift in and out of alignment rather than marching in a
    // rigid row — modulo is applied once, after `speed`, on raw time.
    final raw = time * speed * cycles / periodSeconds + phase;
    final rawT = raw - raw.floorToDouble();
    // Ease in/out rather than linear — gives the rise a gentler, more
    // organic feel instead of a mechanical constant-speed scroll.
    final t = Curves.easeInOutSine.transform(rawT);

    final streakLen = size.height * lengthFraction;
    final headY = size.height + streakLen - t * (size.height + streakLen * 2);
    final tailY = headY + streakLen;
    // A little horizontal sway so the streaks don't feel like they're on
    // rails — small enough to still read as "rising", not wandering.
    final sway = math.sin(rawT * math.pi * 2 + phase * math.pi) * size.width * 0.02;
    final dx = size.width * x + sway;

    final linePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [tint.withValues(alpha: 0), tint.withValues(alpha: alpha)],
      ).createShader(Rect.fromLTRB(dx - 1, tailY, dx + 1, headY))
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0);
    canvas.drawLine(Offset(dx, tailY), Offset(dx, headY), linePaint);

    // A faint, soft-edged head at the leading tip — just enough to read as
    // light drifting through, not a bright accent.
    final headPaint = Paint()
      ..color = tint.withValues(alpha: (alpha * 1.3).clamp(0.0, 1.0))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 1.2);
    canvas.drawCircle(Offset(dx, headY), width * 0.7, headPaint);
  }

  @override
  bool shouldRepaint(covariant _SignalPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.tint != tint ||
      oldDelegate.speed != speed ||
      oldDelegate.opacity != opacity;
}
