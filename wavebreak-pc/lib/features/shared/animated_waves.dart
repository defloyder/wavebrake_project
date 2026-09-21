import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/wb_colors.dart';

/// A handful of slow, layered sine waves drifting across the bottom of the
/// screen. [speed] and [amplitude] are multipliers (1.0 = calm default) so
/// callers can tie liveliness to app state — e.g. faster/bigger while
/// connected — without ever feeling frantic.
class AnimatedWaves extends StatefulWidget {
  const AnimatedWaves({
    super.key,
    this.tint,
    this.speed = 1.0,
    this.amplitude = 1.0,
    this.opacity = 1.0,
    this.lineCount = 4,
  });

  final Color? tint;
  final double speed;
  final double amplitude;
  final double opacity;
  final int lineCount;

  @override
  State<AnimatedWaves> createState() => _AnimatedWavesState();
}

const _wavePeriod = Duration(seconds: 10);

class _AnimatedWavesState extends State<AnimatedWaves>
    with SingleTickerProviderStateMixin {
  // Ticks every frame just to trigger rebuilds; the actual phase fed to the
  // painter comes from the wall clock (below), not this controller's own
  // value, so every AnimatedWaves instance on screen — rail, Home, Settings
  // — stays in lockstep regardless of when each one happened to mount.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _wavePeriod,
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
          // Raw, never-wrapped elapsed time — NOT pre-reduced to a [0,1)
          // progress fraction before `speed` is applied. Wrapping first and
          // multiplying by speed afterwards means every instance snaps back
          // in sync every `_wavePeriod`, but at any speed other than a whole
          // number that snap lands on a different sine value than where the
          // curve had just reached, i.e. a visible jump. Feeding raw time
          // straight into sin() avoids that entirely — sin() is already
          // periodic, so there's nothing to wrap by hand.
          final nowSeconds = DateTime.now().millisecondsSinceEpoch / 1000;
          return CustomPaint(
            painter: _WavesPainter(
              time: nowSeconds,
              periodSeconds: _wavePeriod.inMilliseconds / 1000,
              tint: tint,
              speed: widget.speed.clamp(0.4, 2.6),
              amplitude: widget.amplitude.clamp(0.3, 2.2),
              opacity: widget.opacity,
              lineCount: widget.lineCount,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _WavesPainter extends CustomPainter {
  const _WavesPainter({
    required this.time,
    required this.periodSeconds,
    required this.tint,
    required this.speed,
    required this.amplitude,
    required this.opacity,
    required this.lineCount,
  });

  final double time;
  final double periodSeconds;
  final Color tint;
  final double speed;
  final double amplitude;
  final double opacity;
  final int lineCount;

  static const _baseSpecs = [
    (baseline: 0.70, amp: 18.0, wavelength: 1.3, dir: 1.0, alpha: 0.09),
    (baseline: 0.78, amp: 24.0, wavelength: 1.05, dir: -0.75, alpha: 0.08),
    (baseline: 0.86, amp: 15.0, wavelength: 1.65, dir: 1.35, alpha: 0.065),
    (baseline: 0.92, amp: 10.0, wavelength: 2.1, dir: -1.1, alpha: 0.05),
    (baseline: 0.97, amp: 7.0, wavelength: 2.6, dir: 0.85, alpha: 0.04),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final specs = _baseSpecs.take(lineCount.clamp(1, _baseSpecs.length));
    for (final spec in specs) {
      _line(
        canvas,
        size,
        baseline: spec.baseline,
        amplitude: spec.amp * amplitude,
        wavelength: spec.wavelength,
        speed: spec.dir * speed,
        alpha: spec.alpha * opacity,
      );
    }
  }

  void _line(
    Canvas canvas,
    Size size, {
    required double baseline,
    required double amplitude,
    required double wavelength,
    required double speed,
    required double alpha,
  }) {
    if (alpha <= 0) return;
    final paint = Paint()
      ..color = tint.withValues(alpha: alpha.clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final path = Path();
    final phase = (time / periodSeconds) * math.pi * 2 * speed;
    const steps = 56;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = size.width * t;
      final y = size.height * baseline +
          math.sin(t * math.pi * 2 * wavelength + phase) * amplitude;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavesPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.tint != tint ||
      oldDelegate.speed != speed ||
      oldDelegate.amplitude != amplitude ||
      oldDelegate.opacity != opacity;
}
