import '../../core/theme/wb_theme.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

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
  // One frame clock for the whole simulation: the water moves on real
  // elapsed time, never only when a new speed sample arrives.
  late final Ticker _ticker = createTicker(_tick);
  Duration? _lastElapsed;

  final _water = _WaterSim();

  double _animatedFraction = 0;

  // 0..1: how strongly water pours in from the top-left corner. Eases in
  // when a test starts and dries up when it ends.
  double _pour = 0;

  // Reduce motion: the water stays still (read in build, not per tick).
  bool _still = false;

  // A short, one-shot "just finished" pulse — makes `done` read as an
  // event rather than the water simply going still.
  late final AnimationController _settleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void didUpdateWidget(covariant WaveMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    final justFinished =
        oldWidget.visualState == WaveMeterVisualState.running &&
            widget.visualState != WaveMeterVisualState.running;
    if (justFinished) {
      _settleController.forward(from: 0);
      // The final result is exact, not wherever the easing happened to be.
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
    _ticker.dispose();
    _settleController.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = _lastElapsed == null
        ? 1 / 60
        : ((elapsed - _lastElapsed!).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastElapsed = elapsed;
    final running = widget.visualState == WaveMeterVisualState.running;
    final target = widget.visualState == WaveMeterVisualState.idle
        ? 0.0
        : (widget.valueMbps / widget.maxMbps).clamp(0.0, 1.0);
    // Frame-rate independent easing toward the reading and the pour.
    _animatedFraction +=
        (target - _animatedFraction) * (1 - math.pow(0.92, dt * 60));
    _pour += ((running ? 1.0 : 0.0) - _pour) *
        (1 - math.pow(running ? 0.94 : 0.965, dt * 60));
    _water.step(
      _still ? 0 : dt,
      level: _animatedFraction,
      pour: _pour,
      running: running,
    );
    if (mounted) setState(() {});
  }

  Color get _tint => switch (widget.visualState) {
        WaveMeterVisualState.idle => WbColors.ice60,
        WaveMeterVisualState.running => context.accent,
        // Done reads as a different hue, not just "the number stopped".
        WaveMeterVisualState.done => WbColors.oceanTeal,
        WaveMeterVisualState.failed => WbColors.error,
      };

  @override
  Widget build(BuildContext context) {
    _still = MediaQuery.disableAnimationsOf(context);
    // The number reads off the same eased fraction the water level does,
    // so both move together.
    final numberText = widget.visualState == WaveMeterVisualState.idle
        ? '–'
        : _formatAnimatedMbps(_animatedFraction * widget.maxMbps);
    return AnimatedBuilder(
      animation: _settleController,
      builder: (context, _) => CustomPaint(
        painter: _WaveMeterPainter(
          water: _water,
          fraction: _animatedFraction,
          color: _tint,
          settle: _settleController.value,
          isDone: widget.visualState == WaveMeterVisualState.done,
          pour: _pour,
        ),
        child: _MeterCenter(
          visualState: widget.visualState,
          numberText: numberText,
          unit: widget.unit,
          label: widget.label,
          tint: _tint,
        ),
      ),
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
/// The water in the cube, in panel units (0..1 on both axes, y down):
/// a surface of spring columns (waves run, reflect off the walls and die
/// out) and drops of water pouring in from the top-left corner on a
/// ballistic arc. Where a drop lands it pushes the surface down — the
/// ripple spreads — and throws up spray (owner, 14.10: "like live water
/// that pours in, falls and moves, with physics", not a thin stream).
class _WaterSim {
  static const columns = 60;
  final List<double> _h = List.filled(columns, 0); // offset from the level
  final List<double> _v = List.filled(columns, 0);
  final List<_Drop> drops = [];
  final math.Random _rng = math.Random(7);

  /// Where the still surface sits: a thin layer when empty, near the top
  /// at full scale.
  double level = 0.97;
  double _emit = 0;
  double _ambient = 0;
  double _time = 0;

  double get time => _time;

  /// Surface height at [x] (0..1), with the column offsets.
  double surfaceAt(double x) {
    final f = (x.clamp(0.0, 1.0)) * (columns - 1);
    final i = f.floor().clamp(0, columns - 2);
    final t = f - i;
    return level + _h[i] * (1 - t) + _h[i + 1] * t;
  }

  double columnY(int i) => level + _h[i];

  void step(double dt,
      {required double level, required double pour, required bool running}) {
    if (dt <= 0) return;
    _time += dt;
    this.level = 0.975 - level.clamp(0.0, 1.0) * 0.9;

    // Fixed sub-steps: the spring maths stays stable at any frame rate.
    const sub = 1 / 120;
    var left = dt;
    while (left > 1e-6) {
      final h = math.min(sub, left);
      left -= h;
      _springs(h / sub);
    }

    // A breath of wind on the surface while measuring.
    if (running) {
      _ambient += dt;
      while (_ambient > 0.25) {
        _ambient -= 0.25;
        _v[_rng.nextInt(columns)] += (_rng.nextDouble() - 0.5) * 0.0018;
      }
    }

    // New water: a gush when the line is fast, a trickle when slow.
    // It comes in gushes, like water poured from a jug, not a steady jet.
    final gush = 0.55 + 0.45 * math.sin(_time * 2.6) * math.sin(_time * 0.9 + 1);
    _emit += dt * pour * gush * (26 + 70 * level.clamp(0.0, 1.0));
    while (_emit >= 1) {
      _emit -= 1;
      _spawn(level);
    }

    // A copy: landing drops throw new spray into the list.
    for (final d in List.of(drops)) {
      d.vy += 2.4 * dt;
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      if (d.x > 0.985) {
        d.x = 0.985;
        d.vx = -d.vx * 0.35;
      }
      if (d.x < 0.015) {
        d.x = 0.015;
        d.vx = -d.vx * 0.35;
      }
      final surface = surfaceAt(d.x);
      if (d.vy > 0 && d.y >= surface) {
        d.dead = true;
        _land(d, surface);
      }
    }
    drops.removeWhere((d) => d.dead);
    // Bounded: no more drops than look like water.
    if (drops.length > 260) drops.removeRange(0, drops.length - 260);
  }

  void _springs(double k) {
    const tension = 0.022, damping = 0.035, spread = 0.24;
    for (var i = 0; i < columns; i++) {
      final a = -tension * _h[i] - damping * _v[i];
      _v[i] += a * k;
      _h[i] += _v[i] * k;
    }
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < columns; i++) {
        if (i > 0) {
          final d = spread * (_h[i] - _h[i - 1]) * k;
          _v[i - 1] += d;
        }
        if (i < columns - 1) {
          final d = spread * (_h[i] - _h[i + 1]) * k;
          _v[i + 1] += d;
        }
      }
    }
    for (var i = 0; i < columns; i++) {
      _h[i] = _h[i].clamp(-0.12, 0.12);
    }
  }

  void _spawn(double strength) {
    // Down the left wall from the top-left corner, the way water poured
    // into a glass runs down its side (owner, 14.10: a jet across the
    // middle looked wrong) — only a fast line throws it a little further.
    final r = 0.008 + _rng.nextDouble() * 0.010 + strength * 0.004;
    drops.add(_Drop(
      x: 0.018 + _rng.nextDouble() * 0.025,
      y: 0.02 + _rng.nextDouble() * 0.03,
      vx: 0.03 + _rng.nextDouble() * 0.08 + strength * 0.10,
      vy: 0.08 + _rng.nextDouble() * 0.12,
      r: r,
    ));
  }

  void _land(_Drop d, double surface) {
    final i = (d.x * (columns - 1)).round().clamp(0, columns - 1);
    // The surface gives way under the drop's weight and speed.
    final push = d.vy * d.r * (d.splash ? 0.35 : 1.15);
    _v[i] += push;
    if (i > 0) _v[i - 1] += push * 0.5;
    if (i < columns - 1) _v[i + 1] += push * 0.5;
    if (d.splash) return;
    // Spray: a couple of small drops thrown back up and sideways.
    final n = d.r > 0.012 ? 2 : (_rng.nextDouble() < 0.6 ? 1 : 0);
    for (var k = 0; k < n; k++) {
      drops.add(_Drop(
        x: d.x,
        y: surface - 0.004,
        vx: (_rng.nextDouble() - 0.35) * 0.45,
        vy: -(0.25 + _rng.nextDouble() * 0.45) * math.min(1.6, d.vy),
        r: d.r * (0.35 + _rng.nextDouble() * 0.25),
        splash: true,
      ));
    }
  }
}

class _Drop {
  _Drop({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    this.splash = false,
  });

  double x, y, vx, vy;

  /// Radius as a share of the panel's width.
  final double r;
  final bool splash;
  bool dead = false;
}

class _WaveMeterPainter extends CustomPainter {
  _WaveMeterPainter({
    required this.water,
    required this.fraction,
    required this.color,
    required this.settle,
    required this.isDone,
    required this.pour,
  });

  final _WaterSim water;
  final double fraction;
  final Color color;

  /// 0..1 one-shot progress through the "just finished" pulse.
  final double settle;
  final bool isDone;
  final double pour;

  static const _radius = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_radius),
    );

    // A soft glow behind the panel, brighter right after finishing.
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
            Color.lerp(WbColors.midnight, color, 0.12)!,
            Color.lerp(WbColors.midnight, WbColors.card, 0.65)!,
          ],
          stops: const [0, 0.6, 1],
        ).createShader(Offset.zero & size),
    );

    // Where the water comes in: a faint light in the top-left corner.
    if (pour > 0.02) {
      final c = Offset(size.width * 0.04, size.height * 0.05);
      canvas.drawCircle(
        c,
        size.width * 0.16,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: 0.22 * pour),
            color.withValues(alpha: 0),
          ]).createShader(
              Rect.fromCircle(center: c, radius: size.width * 0.16)),
      );
    }

    // The body of water: a smooth curve through the spring columns.
    const n = _WaterSim.columns;
    Offset col(int i) =>
        Offset(size.width * i / (n - 1), size.height * water.columnY(i));
    final surface = Path()..moveTo(col(0).dx, col(0).dy);
    for (var i = 0; i < n - 1; i++) {
      final a = col(i), b = col(i + 1);
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      surface.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
    }
    surface.lineTo(col(n - 1).dx, col(n - 1).dy);
    final body = Path.from(surface)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final top = size.height * water.level;
    _goo(canvas, size, body);
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.62 + fraction * 0.12),
            Color.lerp(color, WbColors.midnight, 0.78)!.withValues(alpha: 0.94),
          ],
        ).createShader(Rect.fromLTRB(0, top - 20, size.width, size.height)),
    );
    // Light on the surface.
    canvas.drawPath(
      surface,
      Paint()
        ..color = Color.lerp(color, Colors.white, 0.6)!.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 + fraction * 1.2
        ..strokeCap = StrokeCap.round,
    );
    _glints(canvas, size);

    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = WbColors.ice08
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  /// The falling water as one liquid: drops drawn as discs, blurred and
  /// cut at an alpha threshold, so neighbours run together into a pouring
  /// sheet and melt into the surface where they land (metaballs) — not a
  /// row of separate dashes.
  void _goo(Canvas canvas, Size size, Path body) {
    if (water.drops.isEmpty) return;
    final sigma = size.width * 0.012;
    final dropColor = Color.lerp(color, Colors.white, 0.3)!;
    canvas.saveLayer(
      Offset.zero & size,
      Paint()
        ..imageFilter = ui.ImageFilter.compose(
          outer: const ColorFilter.matrix(<double>[
            1, 0, 0, 0, 0, //
            0, 1, 0, 0, 0, //
            0, 0, 1, 0, 0, //
            0, 0, 0, 24, -10 * 255, //
          ]),
          inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        ),
    );
    final fill = Paint()..color = dropColor;
    canvas.drawPath(body, fill);
    for (final d in water.drops) {
      final p = Offset(d.x * size.width, d.y * size.height);
      final r = d.r * size.width * (d.splash ? 1.2 : 1.7);
      // A falling drop is a little longer than wide.
      final stretch = d.splash ? 1.0 : 1.0 + (d.vy * 0.35).clamp(0.0, 0.8);
      canvas.drawOval(
          Rect.fromCenter(center: p, width: r * 2, height: r * 2 * stretch),
          fill);
    }
    canvas.restore();
  }

  static final List<({double x, double y, double phase})> _seeds =
      List.generate(11, (i) {
    final rng = math.Random(i * 733 + 11);
    return (
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      phase: rng.nextDouble() * math.pi * 2
    );
  });

  /// Sunlight glints in the water body, twinkling on their own clock.
  void _glints(Canvas canvas, Size size) {
    final threshold = 1 - (0.3 + fraction * 0.4);
    for (final seed in _seeds) {
      final surfaceY = size.height * water.surfaceAt(seed.x);
      final floor = size.height - 6;
      if (surfaceY >= floor) continue;
      final y = surfaceY + 6 + seed.y * (floor - surfaceY);
      final twinkle = math.sin(water.time * 2.4 + seed.phase) * 0.5 + 0.5;
      if (twinkle <= threshold) continue;
      final strength =
          ((twinkle - threshold) / (1 - threshold)).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(size.width * seed.x, y),
        0.7 + strength * 1.5,
        Paint()
          ..color = Colors.white
              .withValues(alpha: (strength * 0.85).clamp(0.0, 0.85)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveMeterPainter oldDelegate) => true;
}
