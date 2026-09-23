import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/wb_colors.dart';

/// What the meter visually communicates, independent of the exact
/// [SpeedTestStatus] driving it (kept decoupled so this widget doesn't
/// need to import the controller) — [WaveMeter.visualState] maps
/// `testingLatency`/`testingDownload`/`testingUpload` all to `running`,
/// since the meter itself only needs to know "is something actively
/// being measured right now," not which leg.
enum WaveMeterVisualState { idle, running, done, failed }

/// A circular "porthole" whose water level rises with throughput and
/// whose surface never sits still while a measurement is in flight — the
/// wave motif carried into the one screen most likely to be watched
/// closely while it runs, replacing a generic speedometer arc with
/// something that actually reads as WAVEBREAK's own visual language.
///
/// Two things move independently every frame, not just when a new
/// sample arrives (samples are throttled to a few times a second — see
/// SpeedTestService's own comment — so anything driven only by samples
/// would look like it stutters/freezes between them):
///  - the fill level (AND the number displayed in the center — both
///    read the same animated fraction, see build() below) eases toward
///    the latest value every frame, a manual exponential catch-up
///    rather than a fixed-duration tween, so a fast run of samples
///    doesn't fight a previous still-in-flight animation. [valueMbps]
///    itself is expected to already be pre-smoothed by the caller (see
///    SpeedTestController's own EMA over raw samples) — this animation
///    is what makes the TRANSITION between those already-smoothed
///    values continuous, not what removes sample-to-sample noise; doing
///    both jobs in one place used to mean a still-noisy raw target could
///    out-pace this catch-up and read as jumpy regardless.
///  - the water's surface keeps moving on a real wall-clock-driven sine,
///    exactly like [AnimatedWaves]' own background waves, so "in
///    progress" always reads as alive even during a brief lull between
///    samples — never frozen, never ambiguous with "finished" or "stuck"
class WaveMeter extends StatefulWidget {
  const WaveMeter({
    super.key,
    required this.visualState,
    required this.valueMbps,
    required this.maxMbps,
    required this.unit,
    required this.label,
  });

  final WaveMeterVisualState visualState;
  final double valueMbps;
  final double maxMbps;
  final String unit;
  final String label;

  @override
  State<WaveMeter> createState() => _WaveMeterState();
}

/// Same "≥100 gets no decimal" rule the old SpeedometerGauge and the
/// result cards elsewhere on this screen use — kept here too since the
/// displayed number is now derived from the meter's own continuously
/// animated fraction (see class doc) rather than passed in pre-formatted.
String _formatAnimatedMbps(double value) =>
    value.toStringAsFixed(value >= 100 ? 0 : 1);

class _WaveMeterState extends State<WaveMeter> with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  double _animatedFraction = 0;

  // A short, one-shot "just finished" pulse — separate from the
  // continuous wave motion above, this is what makes `done` read as a
  // distinct EVENT (a settle/confirm moment) rather than the wave simply
  // stopping. Triggered once per done/failed transition, not repeated.
  late final AnimationController _settleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(covariant WaveMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    final justFinished =
        oldWidget.visualState == WaveMeterVisualState.running &&
            widget.visualState != WaveMeterVisualState.running;
    if (justFinished) {
      _settleController.forward(from: 0);
      // The catch-up animation is deliberately still mid-chase most of
      // the time a real sample arrives (that's what makes it read as
      // continuous motion) — but the FINAL result has to be exact, not
      // wherever an asymptotic catch-up happened to be sitting the
      // instant the test ended. Snap straight to the real value the
      // moment a leg actually finishes rather than trusting the catch-up
      // to have fully converged by then.
      _animatedFraction = (widget.valueMbps / widget.maxMbps).clamp(0.0, 1.0);
    }
    if (widget.visualState == WaveMeterVisualState.idle &&
        oldWidget.visualState != WaveMeterVisualState.idle) {
      _settleController.reset();
      _animatedFraction = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _settleController.dispose();
    super.dispose();
  }

  Color get _tint => switch (widget.visualState) {
        WaveMeterVisualState.idle => WbColors.ice60,
        WaveMeterVisualState.running => WbColors.waveCyan,
        // Deliberately a different hue from the running state's cyan —
        // "the number stopped changing" isn't enough on its own to read
        // as done; a genuinely different color is (see class doc).
        WaveMeterVisualState.done => WbColors.oceanTeal,
        WaveMeterVisualState.failed => WbColors.error,
      };

  bool get _calm => widget.visualState != WaveMeterVisualState.running;

  @override
  Widget build(BuildContext context) {
    final target = widget.visualState == WaveMeterVisualState.idle
        ? 0.0
        : (widget.valueMbps / widget.maxMbps).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _settleController]),
      builder: (context, _) {
        // Exponential catch-up toward the target every frame (~60x/sec)
        // rather than a fixed-duration tween restarted on every sample —
        // a burst of quick samples just keeps nudging this smoothly
        // instead of each one cutting off the previous animation.
        _animatedFraction += (target - _animatedFraction) * 0.08;
        final nowSeconds = DateTime.now().millisecondsSinceEpoch / 1000;
        // The displayed number reads off this SAME animated fraction,
        // not the raw widget.valueMbps directly — that used to be the
        // actual bug behind "the numbers jump around chaotically": the
        // fill level was smoothed, but the number sat on this widget's
        // `child:` (a static subtree AnimatedBuilder deliberately never
        // rebuilds per-frame) reading the un-animated value straight
        // through, so it hard-cut to every new sample while the wave
        // eased. Computing it here means both move together, at the
        // same rate, off the same number. (No `child:` optimization
        // here as a result — the center content genuinely does need to
        // rebuild every frame for this to work; a single dedicated
        // full-screen meter is exactly the case where that cost is
        // fine, unlike a widget instantiated per list row.)
        final numberText = widget.visualState == WaveMeterVisualState.idle
            ? '–'
            : _formatAnimatedMbps(_animatedFraction * widget.maxMbps);
        return CustomPaint(
          painter: _WaveMeterPainter(
            fraction: _animatedFraction,
            time: nowSeconds,
            color: _tint,
            calm: _calm,
            settle: _settleController.value,
            isDone: widget.visualState == WaveMeterVisualState.done,
          ),
          child: _MeterCenter(
            visualState: widget.visualState,
            numberText: numberText,
            unit: widget.unit,
            label: widget.label,
            tint: _tint,
          ),
        );
      },
    );
  }
}

class _MeterCenter extends StatelessWidget {
  const _MeterCenter({
    required this.visualState,
    required this.numberText,
    required this.unit,
    required this.label,
    required this.tint,
  });

  final WaveMeterVisualState visualState;
  final String numberText;
  final String unit;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Text(
                  numberText,
                  key: ValueKey(numberText),
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: WbColors.ice,
                    height: 1,
                  ),
                ),
              ),
              // A settle checkmark — the concrete "distinct done state"
              // the redesign asked for, not just a color change. Scales
              // in once, doesn't loop/pulse (that would read as still
              // "in progress").
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: visualState == WaveMeterVisualState.done
                    ? Padding(
                        key: const ValueKey('check'),
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: tint.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child:
                              Icon(Icons.check_rounded, size: 17, color: tint),
                        ),
                      )
                    : visualState == WaveMeterVisualState.failed
                        ? Padding(
                            key: const ValueKey('warn'),
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(Icons.priority_high_rounded,
                                size: 20, color: tint),
                          )
                        : const SizedBox.shrink(key: ValueKey('none')),
              ),
            ],
          ),
          const SizedBox(height: 2),
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
          // A subtle pulse while running is the "still alive, still
          // measuring" signal for the text label itself (the wave
          // surface underneath already carries most of that, this
          // reinforces it right where the eye is reading the phase
          // name) — done/failed/idle hold steady, no pulsing, which is
          // itself part of what makes "finished" read as finished.
          _PhaseLabel(
            label: label,
            color: tint,
            pulsing: visualState == WaveMeterVisualState.running,
          ),
        ],
      ),
    );
  }
}

class _PhaseLabel extends StatefulWidget {
  const _PhaseLabel({
    required this.label,
    required this.color,
    required this.pulsing,
  });

  final String label;
  final Color color;
  final bool pulsing;

  @override
  State<_PhaseLabel> createState() => _PhaseLabelState();
}

class _PhaseLabelState extends State<_PhaseLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PhaseLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulsing) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = widget.pulsing ? 0.65 + _controller.value * 0.35 : 1.0;
        return Opacity(opacity: opacity, child: child);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Text(
          widget.label,
          key: ValueKey(widget.label),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: widget.color,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _WaveMeterPainter extends CustomPainter {
  _WaveMeterPainter({
    required this.fraction,
    required this.time,
    required this.color,
    required this.calm,
    required this.settle,
    required this.isDone,
  });

  final double fraction;
  final double time;
  final Color color;
  final bool calm;

  /// 0..1 one-shot progress through the "just finished" pulse.
  final double settle;
  final bool isDone;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;

    // A soft glow behind the porthole — brighter right after finishing
    // (the settle pulse), otherwise a steady low-key wash tied to the
    // current tint so the meter doesn't read as a flat cutout against
    // the ocean background behind it.
    final glowAlpha = 0.10 + (isDone ? (1 - settle) * 0.18 : 0.0);
    canvas.drawCircle(
      center,
      radius + 14 + (isDone ? (1 - settle) * 10 : 0),
      Paint()
        ..color = color.withValues(alpha: glowAlpha.clamp(0.0, 0.4))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    // Outer ring / track.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = WbColors.ice08
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // The fill itself, clipped to the circle.
    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: radius - 2)));

    final top = center.dy - radius;
    final bottom = center.dy + radius;
    final levelY = bottom - fraction * (bottom - top);

    // Turbulence scales with both throughput (a faster result looks
    // livelier, not just "more full") and whether a measurement is
    // actually in flight — calm() flattens it right down for
    // idle/done/failed so a finished test visibly settles rather than
    // sloshing forever.
    //
    // Real-device feedback this tuning exists to fix: "screaming crazy
    // jittery" — the EMA smoothing added earlier fixed the underlying
    // NUMBER's noise, but this surface motion is a separate concern
    // entirely (it runs off wall-clock time, not the measured value's
    // own noise) and was independently too aggressive: amplitude used to
    // reach ~12.5px in a small circle, the wave's phase could complete a
    // full cycle in ~3 seconds at high throughput, AND a second wave
    // layer moved in the OPPOSITE direction at a different wavelength —
    // two counter-rotating waves crossing through each other's phase
    // constantly produces exactly the kind of unpredictable, beating
    // interference pattern that reads as chaotic rather than a single
    // calm undulation. Fixed by roughly halving the amplitude/speed
    // ranges, lengthening the wavelength (fewer, broader undulations
    // read as calmer than several tight ones), and making the second
    // layer drift the SAME direction as the first (a subtle depth cue,
    // not a competing pattern) at a much lower amplitude.
    final amplitude = calm ? 1.2 : 2.5 + 4.0 * fraction;
    final speed = calm ? 0.35 : 0.55 + fraction * 0.45;
    final wavelength = radius * 1.9;

    _fillWave(canvas, size, center, radius, levelY,
        amplitude: amplitude,
        wavelength: wavelength,
        speed: speed,
        phaseOffset: 0,
        alpha: 0.85);
    _fillWave(canvas, size, center, radius, levelY,
        amplitude: amplitude * 0.4,
        wavelength: wavelength * 1.3,
        speed: speed * 0.7,
        phaseOffset: math.pi / 3,
        alpha: 0.22);

    canvas.restore();
  }

  void _fillWave(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    double levelY, {
    required double amplitude,
    required double wavelength,
    required double speed,
    required double phaseOffset,
    required double alpha,
  }) {
    final path = Path();
    final left = center.dx - radius - 4;
    final right = center.dx + radius + 4;
    final bottom = center.dy + radius + 4;
    path.moveTo(left, bottom);
    const steps = 40;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = left + (right - left) * t;
      final y = levelY +
          math.sin(
                  (x / wavelength) * 2 * math.pi + time * speed + phaseOffset) *
              amplitude;
      path.lineTo(x, y);
    }
    path.lineTo(right, bottom);
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(covariant _WaveMeterPainter oldDelegate) => true;
}
