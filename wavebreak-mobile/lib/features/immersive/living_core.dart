import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env/app_env.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/personalization_controller.dart';
import '../../services/vpn/connection_manager.dart';
import '../shared/wave_params.dart';
import 'effects_quality.dart';
import 'immersive_clock.dart';
import 'orbit_frame.dart';
import 'soft_glow.dart';
import 'sphere_assets.dart';

/// Sphere size for the screen width (V5 spec: 278 tablet, 240 phone,
/// 210 narrow, 185 at 320 px).
double livingCoreDiameter(double screenWidth) {
  if (screenWidth <= 320) return 185;
  if (screenWidth <= 380) return 210;
  if (screenWidth < 760) return 240;
  return 278;
}

/// The stage around the core: tall enough for the orbit waves, full width,
/// with [overlay] (e.g. the side readouts) laid over it. The readouts share
/// space with the waves, as in the mockup; where the overlay paints nothing
/// taps fall through to the sphere.
class CoreStage extends StatelessWidget {
  const CoreStage({
    super.key,
    required this.diameter,
    required this.core,
    this.overlay,
  });

  final double diameter;
  final Widget core;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: diameter * 1.27,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: core),
          if (overlay != null) Positioned.fill(child: overlay!),
        ],
      ),
    );
  }
}

/// The V5 connect core: a crimson glass sphere with the Earth texture
/// rotating on it (shaders/living_sphere.frag), 18 orbiting waves with
/// particles sharing one 3D model and depth test, inward fronts while
/// connecting and outward fronts on success. The tap area is the sphere
/// itself; everything around it ignores the pointer.
///
/// Fills its parent and centers the sphere in it.
class LivingCore extends ConsumerStatefulWidget {
  const LivingCore({
    super.key,
    required this.status,
    required this.enabled,
    required this.onPressed,
    this.diameter = 240,
  });

  final ConnectionStatus status;
  final bool enabled;
  final VoidCallback onPressed;
  final double diameter;

  @override
  ConsumerState<LivingCore> createState() => _LivingCoreState();
}

enum _Phase { idle, connecting, connected, error }

_Phase _phaseOf(ConnectionStatus s) => switch (s) {
      ConnectionStatus.requestingProfile ||
      ConnectionStatus.connecting ||
      ConnectionStatus.configPending =>
        _Phase.connecting,
      ConnectionStatus.connected => _Phase.connected,
      ConnectionStatus.error => _Phase.error,
      ConnectionStatus.idle || ConnectionStatus.disconnecting => _Phase.idle,
    };

class _LivingCoreState extends ConsumerState<LivingCore>
    with TickerProviderStateMixin {
  /// The remote / keyboard focus is on the sphere (a ring shows it).
  bool _focused = false;

  late final _energy = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  late final _warn = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  late final _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 260));
  final _motion = _Motion();
  ui.FragmentShader? _shader;
  ui.Image? _texture;
  ui.Image? _mark;

  // The standard WAVEBREAK mark (the one the connect button had before the
  // sphere, WavebreakMark): decoded once, small.
  static Future<ui.Image?>? _markFuture;
  static Future<ui.Image?> _loadMark() async {
    try {
      final data =
          await rootBundle.load('assets/branding/wavebreak_mark_square.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
          targetWidth: 512);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }
  TextPainter? _labelPainter;
  String? _labelText;
  double? _labelDiameter;
  String? _labelFamily;

  TextPainter _labelFor(String text, double d, String? family) {
    if (_labelPainter != null &&
        _labelText == text &&
        _labelDiameter == d &&
        _labelFamily == family) {
      return _labelPainter!;
    }
    _labelPainter?.dispose();
    _labelText = text;
    _labelDiameter = d;
    _labelFamily = family;
    return _labelPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          // The app font (a painter has no DefaultTextStyle of its own).
          fontFamily: family,
          color: const Color(0xFFFFE1E7),
          fontSize: d < 200 ? 10 : 12,
          letterSpacing: 1,
          shadows: const [Shadow(color: Color(0x99200008), blurRadius: 6)],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: d * 0.7);
  }

  @override
  void initState() {
    super.initState();
    _apply(initial: true);
    (_markFuture ??= _loadMark()).then((img) {
      if (mounted && img != null) setState(() => _mark = img);
    });
    SphereAssets.load().then((assets) {
      if (!mounted || assets == null) return;
      setState(() {
        _shader = assets.program.fragmentShader();
        _texture = assets.texture;
      });
    });
  }

  @override
  void didUpdateWidget(covariant LivingCore old) {
    super.didUpdateWidget(old);
    if (_phaseOf(old.status) != _phaseOf(widget.status)) _apply();
  }

  void _apply({bool initial = false}) {
    final phase = _phaseOf(widget.status);
    final previous = _motion.phase;
    _motion
      ..phase = phase
      ..phaseStart = _motion.clock.elapsed;
    // Success fronts only on a real connecting -> connected transition,
    // not when the screen opens on an already running session.
    _motion.successFronts =
        phase == _Phase.connected && previous == _Phase.connecting && !initial;
    final energy = switch (phase) {
      _Phase.idle => 0.0,
      _Phase.connecting => 0.45,
      _Phase.connected => 1.0,
      _Phase.error => 0.25,
    };
    final warn = phase == _Phase.error ? 1.0 : 0.0;
    if (initial) {
      _energy.value = energy;
      _warn.value = warn;
    } else {
      _energy.animateTo(energy, curve: Curves.easeOutCubic);
      _warn.animateTo(warn, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _energy.dispose();
    _warn.dispose();
    _press.dispose();
    _shader?.dispose();
    _labelPainter?.dispose();
    super.dispose();
  }

  String _label() {
    final s = ref.watch(stringsProvider);
    return switch (widget.status) {
      ConnectionStatus.idle => s.coreConnect,
      ConnectionStatus.requestingProfile ||
      ConnectionStatus.connecting =>
        s.coreCancel,
      ConnectionStatus.configPending ||
      ConnectionStatus.connected =>
        s.coreDisconnect,
      ConnectionStatus.disconnecting => s.disconnecting,
      ConnectionStatus.error => s.coreRetry,
    };
  }

  @override
  Widget build(BuildContext context) {
    final time = ImmersiveClock.of(context);
    final frozen = ImmersiveClock.frozen(context);
    final label = _label();
    final d = widget.diameter;
    // The selected location's flag accent, like every other surface; a
    // location change glides the sphere over to the new color.
    final target = ref.watch(appWaveParamsProvider).tint;
    final economy = ref.watch(effectsEconomyProvider);
    // Personalization: Earth (full), Glass (no texture), Minimal (a ring).
    final style = ref.watch(personalizationProvider).sphereStyle;
    final core = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target ?? _CorePainter.baseHue),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, tint, _) => CustomPaint(
      size: Size.infinite,
      painter: _CorePainter(
        repaint: Listenable.merge([time, _energy, _warn, _press]),
        time: time,
        frozen: frozen,
        diameter: d,
        energy: _energy,
        warn: _warn,
        press: _press,
        motion: _motion,
        // Economy effects (older phones): the plain sphere, no shader.
        shader: economy || style != SphereStyle.earth ? null : _shader,
        lite: economy,
        minimal: style == SphereStyle.minimal,
        texture: _texture,
        mark: _mark,
        label: _labelFor(label, d, DefaultTextStyle.of(context).style.fontFamily),
        enabled: widget.enabled,
        tint: tint,
      ),
    ),
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(child: RepaintBoundary(child: core)),
          ),
        ),
        Semantics(
          button: true,
          enabled: widget.enabled,
          label: label,
          // A TV remote / keyboard reaches the sphere too: OK / Enter
          // presses it, a ring shows it has the focus. On a TV it takes
          // the focus first — connecting is what Home is for.
          child: FocusableActionDetector(
            enabled: widget.enabled,
            autofocus: AppEnv.isTv,
            onShowFocusHighlight: (v) => setState(() => _focused = v),
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
                widget.onPressed();
                return null;
              }),
            },
            child: ClipOval(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: widget.enabled ? (_) => _press.forward() : null,
                onTapUp: widget.enabled ? (_) => _press.reverse() : null,
                onTapCancel: widget.enabled ? () => _press.reverse() : null,
                onTap: widget.enabled
                    ? () {
                        HapticFeedback.lightImpact();
                        widget.onPressed();
                      }
                    : null,
                child: Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _focused ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Mutable motion state that survives painter rebuilds: the phase clock
/// and the integrated particle angle (integrated, so the speed-up while
/// connecting doesn't make particles jump).
class _Motion {
  final clock = Stopwatch()..start();
  _Phase phase = _Phase.idle;
  Duration phaseStart = Duration.zero;
  bool successFronts = false;
  double particleAngle = 0;
  double speed = 0.46;
  double? lastT;
  final orbits = OrbitFrame(_CorePainter._bands);

  double get sincePhase => (clock.elapsed - phaseStart).inMicroseconds / 1e6;
}

class _CorePainter extends CustomPainter {
  _CorePainter({
    required Listenable repaint,
    required this.time,
    required this.frozen,
    required this.diameter,
    required this.energy,
    required this.warn,
    required this.press,
    required this.motion,
    required this.shader,
    required this.texture,
    this.mark,
    required this.label,
    required this.enabled,
    required this.tint,
    this.lite = false,
    this.minimal = false,
  }) : super(repaint: repaint);

  final ValueListenable<double> time;
  final bool frozen;
  final double diameter;
  final Animation<double> energy;
  final Animation<double> warn;
  final Animation<double> press;
  final _Motion motion;
  final ui.FragmentShader? shader;
  final ui.Image? texture;

  /// The standard WAVEBREAK mark; the vector W until it is decoded.
  final ui.Image? mark;
  final TextPainter label;
  final bool enabled;

  /// Flag accent to recolor the sphere to (null = keep crimson).
  final Color? tint;

  /// Economy effects (older phones): coarser orbits, no far halves seen
  /// through the glass, no blurred glows.
  final bool lite;

  /// Personalization "Minimal": a light ring around the mark instead of
  /// the sphere, its glass and orbits (cheap on any phone).
  final bool minimal;

  /// The hue the sphere is designed in; [tint] rotates away from it.
  static const baseHue = Color(0xFFFF4C74);

  /// Hue rotation (luminance-preserving matrix) from the designed crimson
  /// to [tint], faded out while the error amber shows. Null when there's
  /// nothing to rotate (no tint, a near-grey tint, or ~the same hue).
  static List<double>? _tintMatrix(Color? tint, double w) {
    final c = tint;
    if (c == null) return null;
    final hsl = HSLColor.fromColor(c);
    if (hsl.saturation < 0.15) return null;
    var deg = hsl.hue - HSLColor.fromColor(baseHue).hue;
    if (deg > 180) deg -= 360;
    if (deg < -180) deg += 360;
    deg *= 1 - w;
    if (deg.abs() < 2) return null;
    final a = deg * math.pi / 180;
    final cs = math.cos(a), sn = math.sin(a);
    return <double>[
      0.213 + cs * 0.787 - sn * 0.213, 0.715 - cs * 0.715 - sn * 0.715,
      0.072 - cs * 0.072 + sn * 0.928, 0, 0, //
      0.213 - cs * 0.213 + sn * 0.143, 0.715 + cs * 0.285 + sn * 0.140,
      0.072 - cs * 0.072 - sn * 0.283, 0, 0, //
      0.213 - cs * 0.213 - sn * 0.787, 0.715 - cs * 0.715 + sn * 0.715,
      0.072 + cs * 0.928 + sn * 0.072, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }

  /// This frame's tint matrix (set at the start of [paint]).
  List<double>? _m;

  /// [c] through the tint matrix (clamped like a color filter would).
  Color _tc(Color c) {
    final m = _m;
    if (m == null) return c;
    final r = c.r, g = c.g, b = c.b;
    return Color.from(
      alpha: c.a,
      red: (m[0] * r + m[1] * g + m[2] * b).clamp(0.0, 1.0),
      green: (m[5] * r + m[6] * g + m[7] * b).clamp(0.0, 1.0),
      blue: (m[10] * r + m[11] * g + m[12] * b).clamp(0.0, 1.0),
    );
  }

  List<Color> _tcs(List<Color> colors) =>
      _m == null ? colors : [for (final c in colors) _tc(c)];

  static const _crimson = Color(0xFFFF4C74);
  static const _amber = Color(0xFFFFA84C);
  static const _bands = 18;
  static const _vertices = 210;
  static const _particles = 78;
  static const _connectingSeconds = 3.4;
  static const _successSeconds = 1.8;
  static const _revolution = 35.7;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final c = size.center(Offset.zero);
    final r = diameter / 2;
    final e = energy.value;
    final w = warn.value;
    final phase = motion.phase;
    final since = motion.sincePhase;
    final connecting = phase == _Phase.connecting;
    final charge = connecting && !frozen
        ? (since / _connectingSeconds).clamp(0.0, 1.0)
        : 0.0;
    final success = !frozen &&
        motion.successFronts &&
        phase == _Phase.connected &&
        since < _successSeconds;

    // Particle angle, integrated so a speed change never teleports them.
    final dt = motion.lastT == null ? 0.0 : (t - motion.lastT!).clamp(0.0, 0.1);
    motion.lastT = t;
    final targetSpeed = connecting ? 1.4 : 0.46;
    motion.speed += (targetSpeed - motion.speed) * (dt * 3).clamp(0.0, 1.0);
    motion.particleAngle += dt * motion.speed;

    // Glass pulse while connecting (1.2 s), a short swell after success.
    final pulse = connecting && !frozen
        ? 0.5 + 0.5 * math.sin(t * 2 * math.pi / 1.2)
        : success
            ? 1 - since / _successSeconds
            : 0.0;
    final scale =
        (1 - press.value * 0.03) * (1 - (connecting ? pulse * 0.015 : 0));

    if (!enabled) {
      canvas.saveLayer(
          // The effects' reach (aura, glow, fronts go up to 1.8 r): a
          // box-sized layer cut them off in a hard edge under the sphere.
          Rect.fromCircle(center: c, radius: r * 2.1),
          Paint()..color = const Color(0x73FFFFFF));
    }

    // Everything but the W emblem and the label follows the flag accent:
    // each color goes through the hue rotation here ([_tc]) — the same
    // result as one color-filtered layer over them (the matrix is linear),
    // without an offscreen buffer the size of the effects every frame.
    _m = _tintMatrix(tint, w);

    _aura(canvas, c, r, t, e, w);
    _shell(canvas, c, r, e, w);

    if (minimal) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(scale);
      canvas.translate(-c.dx, -c.dy);
      _ring(canvas, c, r, e, w, pulse);
      canvas.restore();
    } else {
      // Orbit geometry once for both passes.
      motion.orbits
        ..setFrame(t: t, center: c, rs: r * 0.97, charge: charge)
        ..fillBands(lite ? 84 : _vertices)
        ..fillParticles(_particles, motion.particleAngle);

      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(scale);
      canvas.translate(-c.dx, -c.dy);
      _outerGlow(canvas, c, r, e, w, pulse);
      _sphere(canvas, c, r, t, e, w, pulse);
      // Far halves of the orbits, faint, seen through the glass.
      if (!lite) _ribbons(canvas, r, front: false);
      _glass(canvas, c, r, t, e, w);
      canvas.restore();

      _ribbons(canvas, r, front: true);
    }
    if (connecting && !frozen) _inwardFronts(canvas, c, r, t);
    if (success) _outwardFronts(canvas, c, r, t, since);

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(scale);
    canvas.translate(-c.dx, -c.dy);
    _emblem(canvas, c);
    _label(canvas, c, r);
    canvas.restore();

    if (!enabled) canvas.restore();
  }

  // ── Layers ──────────────────────────────────────────────────────────

  void _aura(Canvas canvas, Offset c, double r, double t, double e, double w) {
    final breathe = 0.5 + 0.5 * math.sin(t * 2 * math.pi / 5);
    final opacity = ui.lerpDouble(0.8 - 0.15 * breathe, 1.0, e)!;
    final radius = r * 1.54 * (1 + 0.03 * breathe * (1 - e));
    final color = _tc(Color.lerp(const Color(0xFFFF2343), _amber, w)!);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: (0.17 + 0.12 * e) * opacity),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.65],
        ).createShader(Rect.fromCircle(center: c, radius: radius)),
    );
  }

  void _shell(Canvas canvas, Offset c, double r, double e, double w) {
    final shellR = r * 1.14;
    final tone = _tc(Color.lerp(const Color(0xFFE15467), _amber, w)!);
    drawSoftRing(canvas, c, shellR,
        _tc(const Color(0xFFFA1830).withValues(alpha: 0.05 + 0.04 * e)), 10, 8);
    canvas.drawCircle(
      c,
      shellR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = tone.withValues(alpha: 0.21 + 0.1 * e),
    );
    // Inner reflex ring, visible top-left and bottom-right only.
    final inner = Rect.fromCircle(center: c, radius: shellR - 5);
    canvas.drawCircle(
      c,
      shellR - 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          transform: const GradientRotation(20 * math.pi / 180),
          colors: _tcs(const [
            Color(0x44FFC4CC),
            Color(0x00FFC4CC),
            Color(0x44FFC4CC),
          ]),
          stops: const [0, 0.45, 1],
        ).createShader(inner),
    );
  }

  void _outerGlow(
      Canvas canvas, Offset c, double r, double e, double w, double pulse) {
    final glow = _tc(Color.lerp(const Color(0xFFFF154B), _amber, w)!);
    // Wide soft glow (0 0 40px idle -> 0 0 34px + 85px connected).
    drawOuterGlow(canvas, c, r * 1.02,
        glow.withValues(alpha: 0.22 + 0.25 * e + 0.15 * pulse), 16 + 10 * e);
    if (e > 0.01) {
      drawOuterGlow(canvas, c, r * 1.05,
          _tc(const Color(0xFFE82744).withValues(alpha: 0.23 * e)), 40);
    }
    // Two thin halo rings just outside the rim (box-shadow spreads).
    final ring2 =
        Color.lerp(const Color(0x45F5385B), const Color(0x7AFF4169), e)!;
    final ring1 =
        _tc(Color.lerp(const Color(0x2D8F1B30), const Color(0x2DB62C47), e)!);
    canvas.drawCircle(
      c,
      r + 3.5 + 0.5 * e,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7 + e
        ..color = _tc(
            w > 0 ? Color.lerp(ring2, const Color(0x2BB67734), w)! : ring2),
    );
    canvas.drawCircle(
      c,
      r + 2 + 0.5 * e,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 + e
        ..color = ring1,
    );
  }

  /// "Minimal" style: a dark disc behind the mark and one lit ring that
  /// brightens with the connection (and pulses while connecting).
  void _ring(
      Canvas canvas, Offset c, double r, double e, double w, double pulse) {
    final color = _tc(Color.lerp(const Color(0xFFFF4C74), _amber, w)!);
    canvas.drawCircle(
      c,
      r * 0.96,
      Paint()
        ..shader = RadialGradient(colors: [
          _tc(const Color(0x33200810)),
          _tc(const Color(0x10200810)),
        ]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    if (!lite) {
      drawSoftRing(canvas, c, r * 0.96,
          color.withValues(alpha: 0.18 + 0.2 * e + 0.15 * pulse), 6, 8);
    }
    canvas.drawCircle(
      c,
      r * 0.96,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 + e
        ..color = color.withValues(alpha: 0.55 + 0.35 * e),
    );
  }

  void _sphere(Canvas canvas, Offset c, double r, double t, double e, double w,
      double pulse) {
    final sh = shader;
    final tex = texture;
    if (sh == null || tex == null || SphereAssets.broken) {
      _fallbackSphere(canvas, c, r, e, w);
      return;
    }
    // The shader draws its disc at 0.90 of half the rect and a halo
    // outside it, so the rect is a bit larger than the sphere.
    final side = diameter / 0.90;
    try {
      sh
        ..setFloat(0, side)
        ..setFloat(1, side)
        ..setFloat(2, t)
        ..setFloat(3, t * 2 * math.pi / _revolution)
        ..setFloat(4, e)
        ..setFloat(5, pulse)
        ..setFloat(6, 0)
        ..setFloat(7, w)
        ..setImageSampler(0, tex, filterQuality: FilterQuality.low);
    } catch (_) {
      // This GPU/driver can't run it: the plain sphere from now on.
      SphereAssets.broken = true;
      _fallbackSphere(canvas, c, r, e, w);
      return;
    }
    canvas.save();
    canvas.translate(c.dx - side / 2, c.dy - side / 2);
    final m = _m;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, side, side),
      Paint()
        ..shader = sh
        ..colorFilter = m == null ? null : ColorFilter.matrix(m),
    );
    canvas.restore();
  }

  void _fallbackSphere(Canvas canvas, Offset c, double r, double e, double w) {
    final rect = Rect.fromCircle(center: c, radius: r);
    final base = [
      const Color(0x53FF9BA5),
      const Color(0x6E940A29),
      const Color(0xE6430B1A),
      const Color(0xDD16010D),
    ];
    final lit = [
      const Color(0x8CFFAEC7),
      const Color(0x6BF22446),
      const Color(0xD966071F),
      const Color(0xFF290518),
    ];
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.34, -0.54),
          radius: 1.1,
          colors: [
            for (var i = 0; i < 4; i++)
              _tc(Color.lerp(
                  Color.lerp(base[i], lit[i], e)!, _amber, w * 0.35)!),
          ],
          stops: const [0, 0.33, 0.75, 1],
        ).createShader(rect),
    );
  }

  void _glass(Canvas canvas, Offset c, double r, double t, double e, double w) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipRRect(RRect.fromRectXY(rect, r, r)); // = the oval, cheaper clip

    // Atmosphere: a crimson band just inside the rim, slow pulse.
    final ar = r * 0.97;
    final atm = _tc(Color.lerp(const Color(0xFFFF2651), _amber, w)!);
    canvas.drawCircle(
      c,
      ar * 1.065,
      Paint()
        ..shader = RadialGradient(
          colors: [
            atm.withValues(alpha: 0),
            atm.withValues(alpha: 0),
            atm.withValues(alpha: 0.48 + 0.06 * math.sin(t * 0.7)),
            atm.withValues(alpha: 0.17),
            atm.withValues(alpha: 0),
          ],
          stops: const [0, 0.906, 0.932, 0.947, 1],
        ).createShader(Rect.fromCircle(center: c, radius: ar * 1.065)),
    );
    canvas.drawCircle(
      c,
      ar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = _tc(
            Color.lerp(const Color(0xB0FFC1D1), const Color(0xB0FFE0B8), w)!),
    );

    // Inset rings (5 px and 11 px inside the rim).
    canvas.drawCircle(
      c,
      r - 5.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..color = _tc(const Color(0x45A31533)),
    );
    canvas.drawCircle(
      c,
      r - 2.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = _tc(
            Color.lerp(const Color(0x30FC5C73), const Color(0x32FF90A9), e)!),
    );

    // Glass reflex: soft top-left highlight and a diagonal sheen.
    final inner = rect.deflate(7);
    canvas.drawOval(
      inner,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.36, -0.52),
          radius: 0.34,
          colors: _tcs(const [Color(0x34FFF2E8), Color(0x00FFF2E8)]),
        ).createShader(inner),
    );
    canvas.drawOval(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          transform: const GradientRotation(-10 * math.pi / 180),
          colors: _tcs(const [
            Color(0x00FFD7E3),
            Color(0x12FFD7E3),
            Color(0x00FFD7E3),
          ]),
          stops: const [0.20, 0.39, 0.57],
        ).createShader(inner),
    );
    canvas.restore();

    // Thin highlight arc across the upper part.
    final d = diameter;
    final arc = Rect.fromLTWH(
        c.dx - r + d * 0.15, c.dy - r + d * 0.09, d * 0.72, d * 0.25);
    canvas.save();
    canvas.translate(arc.center.dx, arc.center.dy);
    canvas.rotate(-17 * math.pi / 180);
    canvas.translate(-arc.center.dx, -arc.center.dy);
    canvas.drawArc(
      arc,
      math.pi * 1.12,
      math.pi * 0.76,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
            colors: _tcs(const [
          Color(0x00FFB9D0),
          Color(0x81FFB9D0),
          Color(0x00FFB9D0),
        ])).createShader(arc),
    );
    canvas.restore();

    // Rim.
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _tc(
            Color.lerp(const Color(0xAAFF718B), const Color(0xFFFFD0A1), w)!),
    );
  }

  /// The orbits and particles in front of the sphere, or (front: false)
  /// their far halves seen through the glass. Geometry from [OrbitFrame],
  /// computed once per frame for both passes.
  void _ribbons(Canvas canvas, double r, {required bool front}) {
    final o = motion.orbits;
    final rs = r * 0.97;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final n = o.vertexCount + 1;
    final xs = o.xs, ys = o.ys, behind = o.behind;
    final hidden = front ? 1 : 0;
    for (var b = _bands - 1; b >= 0; b--) {
      // One addPolygon per visible run instead of a moveTo/lineTo call
      // per vertex: the same path, a fraction of the engine calls (on a
      // phone those per-point calls were most of the sphere's UI time).
      final path = Path();
      var run = <Offset>[];
      final base = b * n;
      for (var i = 0; i < n; i++) {
        final k = base + i;
        if (behind[k] == hidden) {
          if (run.length > 1) path.addPolygon(run, false);
          run = <Offset>[];
          continue;
        }
        run.add(Offset(xs[k], ys[k]));
      }
      if (run.length > 1) path.addPolygon(run, false);
      final cold = b == _bands - 1;
      final color = cold ? const Color(0xFF85EBF9) : _crimson;
      final alpha = (front ? 0.34 : 0.08) * (1 - b / (_bands * 1.15));
      if (b == 0 && front && !lite) {
        drawSoftPath(
            canvas,
            path,
            _tc((cold ? const Color(0xFF45E9FF) : const Color(0xFFFF174C))
                .withValues(alpha: 0.35)),
            4,
            6);
      }
      canvas.drawPath(
        path,
        stroke
          ..strokeWidth = b == 0 ? 1.5 : 0.55
          ..color = _tc(color.withValues(alpha: alpha)),
      );
    }

    final dot = Paint()
      ..color =
          _tc(const Color(0xFFFFA4BE).withValues(alpha: front ? 0.65 : 0.16));
    final glow = Paint()
      ..color = _tc(const Color(0xFFFF416A).withValues(alpha: 0.5))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    for (var i = 0; i < _particles; i++) {
      if (o.pBehind[i] == hidden) continue;
      final big = i % 13 == 0;
      final size = (big ? 1.8 : 0.7) * (1 + o.pz[i] / rs * 0.25);
      final p = Offset(o.px[i], o.py[i]);
      if (big && front && !lite) canvas.drawCircle(p, size * 3, glow);
      canvas.drawCircle(p, size, dot);
    }
  }

  void _front(Canvas canvas, Offset c, double rr, double t, int i, Color color,
      double alpha) {
    final points = <Offset>[
      for (var j = 0; j <= 160; j++)
        () {
          final a = j / 160 * math.pi * 2;
          final rip = 1 + math.sin(a * 5 - t * 2 + i) * 0.023;
          return Offset(c.dx + math.cos(a) * rr * rip,
              c.dy + math.sin(a) * rr * rip * 0.84);
        }(),
    ];
    final path = Path()..addPolygon(points, false);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _tc(color.withValues(alpha: alpha)),
    );
  }

  /// Repeating fronts from the outer field in to the shell.
  void _inwardFronts(Canvas canvas, Offset c, double r, double t) {
    final f = (t * 0.65) % 1;
    for (var i = 0; i < 3; i++) {
      final p = (f + i * 0.28) % 1;
      _front(canvas, c, r * (1.8 - p * 0.72), t, i, const Color(0xFFFF7597),
          (1 - p) * 0.55);
    }
  }

  /// Light fronts leaving the sphere once, after a successful connect.
  void _outwardFronts(
      Canvas canvas, Offset c, double r, double t, double since) {
    final f = since / _successSeconds;
    for (var i = 0; i < 3; i++) {
      final p = (f * 1.3 - i * 0.15);
      if (p <= 0 || p >= 1) continue;
      _front(canvas, c, r * (1 + p * 0.8), t, i, const Color(0xFFFFDAE6),
          (1 - p) * 0.55);
    }
  }

  // ── Emblem and label ────────────────────────────────────────────────

  static final _wShadow = _poly(const [
    3, 20, 18, 17, 29, 33, 44, 12, 57, 12, 42, 35, 53, 43, 71, 17, 86, 15, //
    59, 55, 45, 49, 36, 39, 26, 50,
  ]);
  static final _wMain = _poly(const [
    3, 17, 18, 14, 29, 30, 44, 9, 57, 9, 42, 32, 53, 40, 71, 14, 86, 12, //
    59, 52, 45, 46, 36, 36, 26, 47,
  ]);
  static final _wStripe = _poly(const [
    1,
    34,
    35,
    26,
    64,
    29,
    89,
    24,
    70,
    34,
    42,
    33,
    10,
    40,
  ]);

  static Path _poly(List<double> xy) {
    final p = Path()..moveTo(xy[0], xy[1]);
    for (var i = 2; i < xy.length; i += 2) {
      p.lineTo(xy[i], xy[i + 1]);
    }
    return p..close();
  }

  /// The metallic arctic W (viewBox 90×60, 34 % of the sphere wide).
  /// It never rotates with the surface.
  void _emblem(Canvas canvas, Offset c) {
    final m = mark;
    if (m != null) {
      // The W fills ~95 % of the square image's width and sits a bit
      // below its middle: 40 % of the sphere wide, optically centred.
      final side = diameter * 0.40 / 0.95;
      final dst = Rect.fromCenter(
          center: c.translate(0, -0.042 * side), width: side, height: side);
      canvas.drawImageRect(
        m,
        Rect.fromLTWH(0, 0, m.width.toDouble(), m.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }
    final s = diameter * 0.34 / 90;
    canvas.save();
    canvas.translate(c.dx - 45 * s, c.dy - 30 * s);
    canvas.scale(s);
    final all = Path()
      ..addPath(_wShadow, Offset.zero)
      ..addPath(_wMain, Offset.zero)
      ..addPath(_wStripe, Offset.zero);
    // drop-shadow(0 5px 2px #042245), drop-shadow(0 0 14px #6efff629)
    canvas.drawPath(
      all,
      Paint()
        ..color = const Color(0x296EFFF6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 / s),
    );
    canvas.drawPath(
      all.shift(const Offset(0, 5)),
      Paint()
        ..color = const Color(0xFF042245)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1 / s),
    );
    canvas.drawPath(_wShadow.shift(const Offset(0, 3)),
        Paint()..color = const Color(0xFF05274F));
    canvas.drawPath(
      _wMain,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(3, 9),
          const Offset(44.5, 52),
          const [
            Color(0xFFD2FFFF),
            Color(0xFF35E3F8),
            Color(0xFF0C77B8),
            Color(0xFF093781),
          ],
          const [0, 0.4, 0.55, 1],
        ),
    );
    canvas.drawPath(_wStripe, Paint()..color = const Color(0xD966F1F5));
    canvas.restore();
  }

  void _label(Canvas canvas, Offset c, double r) {
    final tp = label;
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy + r * 0.68 - tp.height));
  }

  @override
  bool shouldRepaint(_CorePainter old) =>
      old.frozen != frozen ||
      old.diameter != diameter ||
      old.shader != shader ||
      old.texture != texture ||
      old.mark != mark ||
      old.label != label ||
      old.enabled != enabled ||
      old.tint != tint ||
      old.lite != lite ||
      old.minimal != minimal ||
      old.time != time;
}
