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

/// A wave breaking against the meter's own glass — the surface curls,
/// throws spray, and never sits still while a measurement is in flight —
/// the brand's own name acted out, rather than a generic gauge (a plain
/// circular "porthole" was tried first and read as just another
/// speedometer; this replaced it). The panel is a rounded square, not a
/// circle, specifically so the crest reads as a horizon line breaking
/// across the whole width rather than curving to fit a dome.
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
  double? _lastFrameSeconds;
  double _spawnAccumulator = 0;
  final math.Random _rng = math.Random(1337);

  // Reused pool, never recreated per frame — advanced in build()'s
  // AnimatedBuilder alongside the fraction catch-up, same "spawn while
  // running, let existing drops finish their arc" pattern the panel used
  // before this widget carried it.
  final List<_FoamDrop> _foam = List.generate(10, (_) => _FoamDrop());

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
        final dt = (_lastFrameSeconds == null ? 1 / 60 : nowSeconds - _lastFrameSeconds!)
            .clamp(0.0, 0.25);
        _lastFrameSeconds = nowSeconds;
        if (widget.visualState == WaveMeterVisualState.running) {
          _spawnAccumulator += dt * (1.0 + _animatedFraction * 7);
          while (_spawnAccumulator >= 1) {
            _spawnAccumulator -= 1;
            for (final drop in _foam) {
              if (drop.t >= 1) {
                drop.respawn(_rng);
                break;
              }
            }
          }
        }
        for (final drop in _foam) {
          drop.advance(dt);
        }
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
            foam: _foam,
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

/// One droplet of spray thrown up where the crest breaks — reused rather
/// than recreated (see [_WaveMeterState._foam]): `t` runs 0..1 over its
/// short life, `t >= 1` marks it dead/available, so the pool never
/// allocates once built. Position is normalized to the panel (0..1 on
/// both axes) so the physics doesn't care about actual pixel size.
class _FoamDrop {
  double t = 1;
  double x = 0.5, y = 0.55, vx = 0, vy = 0, size = 2;

  void respawn(math.Random rng) {
    t = 0;
    x = 0.5 + (rng.nextDouble() - 0.5) * 0.5;
    y = 0.5;
    final angle = -math.pi / 2 + (rng.nextDouble() - 0.5) * 1.5;
    final speed = 0.45 + rng.nextDouble() * 0.55;
    vx = math.cos(angle) * speed;
    vy = math.sin(angle) * speed;
    size = 1.3 + rng.nextDouble() * 2.0;
  }

  void advance(double dt) {
    if (t >= 1) return;
    t += dt / 0.85;
    x += vx * dt;
    y += vy * dt;
    vy += 1.7 * dt; // gravity, same 0..1-of-panel units as y
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
    required this.foam,
  });

  final double fraction;
  final double time;
  final Color color;
  final bool calm;

  /// 0..1 one-shot progress through the "just finished" pulse.
  final double settle;
  final bool isDone;
  final List<_FoamDrop> foam;

  static const _radius = 26.0;

  /// The crest line shared by the fill, the shimmer band and where foam
  /// spawns, so every layer agrees on where "the water" is. A second
  /// harmonic riding the first is what makes this read as a breaking
  /// wave's peaked, slightly asymmetric crest instead of a mechanically
  /// perfect sine — same shape language as the panel this replaced a
  /// circle with, just driven by [fraction] instead of a separately
  /// smoothed level.
  ///
  /// Motion always advances at a fixed rate (`time` only); [calm] and
  /// [fraction] only ever scale amplitude, never the phase multiplier —
  /// see wave_meter.dart's class doc / the jitter post-mortem this same
  /// principle already fixed once for this exact widget.
  double _crestY(Size size, double t) {
    final baseline = size.height * (1 - fraction.clamp(0.0, 1.0));
    final breathe = 0.82 + 0.18 * math.sin(time * 0.1);
    final amp = calm ? 1.0 : 1.0 + fraction * 1.4;
    final swell = (math.sin(t * math.pi * 2 + time * 0.4) * (9 + 6 * amp) +
            math.sin(t * math.pi * 4 - time * 0.65 + 1.3) * (4 + 7 * amp)) *
        breathe *
        (calm ? 0.35 : 1.0);
    return (baseline + swell).clamp(4.0, size.height - 4.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_radius),
    );

    // A soft glow behind the panel — brighter right after finishing (the
    // settle pulse), otherwise a steady low-key wash tied to the current
    // tint so the meter doesn't read as a flat cutout against the ocean
    // background behind it.
    final glowAlpha = 0.10 + (isDone ? (1 - settle) * 0.18 : 0.0);
    canvas.drawRRect(
      rrect.inflate(isDone ? (1 - settle) * 8 : 4),
      Paint()
        ..color = color.withValues(alpha: glowAlpha.clamp(0.0, 0.4))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );

    canvas.save();
    canvas.clipRRect(rrect);

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            WbColors.midnight,
            Color.lerp(WbColors.midnight, color, 0.14)!,
            Color.lerp(WbColors.midnight, WbColors.card, 0.65)!,
          ],
          stops: const [0, 0.6, 1],
        ).createShader(Offset.zero & size),
    );

    const steps = 48;
    final body = Path()..moveTo(0, size.height);
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      body.lineTo(size.width * t, _crestY(size, t));
    }
    body
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.55 + fraction * 0.15),
            Color.lerp(color, WbColors.midnight, 0.8)!.withValues(alpha: 0.92),
          ],
        ).createShader(Offset.zero & size),
    );

    final crest = Path();
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final p = Offset(size.width * t, _crestY(size, t));
      if (i == 0) {
        crest.moveTo(p.dx, p.dy);
      } else {
        crest.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      crest,
      Paint()
        ..color = Color.lerp(color, Colors.white, 0.55)!.withValues(alpha: 0.88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 + fraction * 1.6
        ..strokeCap = StrokeCap.round,
    );

    _shimmer(canvas, size);
    _foamSpray(canvas, size);

    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = WbColors.ice08
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  static final List<({double x, double y, double phase})> _shimmerSeeds =
      List.generate(11, (i) {
    final rng = math.Random(i * 733 + 11);
    return (
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      phase: rng.nextDouble() * math.pi * 2
    );
  });

  /// Sunlight-on-water glints scattered across the filled body — purely
  /// phase-driven (sin(time + seed), never `fraction`), so the twinkle
  /// itself never jitters regardless of how noisy the underlying
  /// measurement is; only how many cross the visibility threshold reacts
  /// to how full the meter currently is.
  void _shimmer(Canvas canvas, Size size) {
    final threshold = 1 - (0.3 + fraction * 0.4);
    for (final seed in _shimmerSeeds) {
      final crestYAtX = _crestY(size, seed.x);
      final floor = size.height - 6;
      if (crestYAtX >= floor) continue;
      final y = crestYAtX + 6 + seed.y * (floor - crestYAtX);
      final twinkle = math.sin(time * 2.4 + seed.phase) * 0.5 + 0.5;
      if (twinkle <= threshold) continue;
      final strength = ((twinkle - threshold) / (1 - threshold)).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(size.width * seed.x, y),
        0.7 + strength * 1.5,
        Paint()..color = Colors.white.withValues(alpha: (strength * 0.85).clamp(0.0, 0.85)),
      );
    }
  }

  /// Spray thrown where the crest breaks — only visible while [foam]'s
  /// pool actually has live drops in it (see [_WaveMeterState.build]),
  /// which itself only spawns while a measurement is running.
  void _foamSpray(Canvas canvas, Size size) {
    for (final drop in foam) {
      if (drop.t >= 1) continue;
      final fade = (1 - drop.t).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(size.width * drop.x, size.height * drop.y),
        drop.size * (0.4 + fade * 0.6),
        Paint()..color = Colors.white.withValues(alpha: (fade * 0.9).clamp(0.0, 0.9)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveMeterPainter oldDelegate) => true;
}
