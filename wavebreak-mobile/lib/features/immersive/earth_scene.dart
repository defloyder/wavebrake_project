import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'effects_quality.dart';
import 'immersive_clock.dart';
import 'sphere_assets.dart';

/// The V5 sign-in scene: near-black space with vector stars on several
/// depth planes, the night Earth rising from the bottom edge (the real UV
/// texture rotating on a sphere — shaders/living_sphere.frag in its natural
/// mode, one turn in ~45.5 s), cold surface currents over it, a blue
/// atmosphere and a wide band of 18 arctic orbit curves with particles that
/// pass behind the planet (depth-tested against the front hemisphere).
///
/// Decoration only: ignores the pointer, excluded from semantics. Driven by
/// the shared [ImmersiveClock] (30 fps, one still frame with reduce-motion).
/// [child] is laid over the scene (headline, captions).
class EarthScene extends ConsumerStatefulWidget {
  const EarthScene({super.key, this.child, this.borderRadius = 0});

  final Widget? child;
  final double borderRadius;

  @override
  ConsumerState<EarthScene> createState() => _EarthSceneState();
}

class _EarthSceneState extends ConsumerState<EarthScene> {
  ui.FragmentShader? _shader;
  ui.Image? _texture;

  @override
  void initState() {
    super.initState();
    SphereAssets.load().then((assets) {
      if (!mounted || assets == null) return;
      setState(() {
        _shader = assets.program.fragmentShader();
        _texture = assets.texture;
      });
    });
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final economy = ref.watch(effectsEconomyProvider);
    final scene = IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _EarthPainter(
              time: ImmersiveClock.of(context),
              shader: _shader,
              texture: _texture,
              economy: economy,
            ),
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        children: [
          Positioned.fill(child: scene),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

class _Star {
  _Star(int i)
      : u = ((i * 73 + 17) % 241) / 241,
        v = ((i * 137 + 31) % 239) / 239,
        z = 0.15 + (i % 11) / 12,
        r = i % 19 == 0
            ? 1.45
            : i % 5 == 0
                ? 0.85
                : 0.45;

  final double u, v, z, r;
}

class _Pt {
  const _Pt(this.x, this.y, this.z);
  final double x, y, z;
}

class _EarthPainter extends CustomPainter {
  _EarthPainter({
    required this.time,
    required this.shader,
    required this.texture,
    required this.economy,
  }) : super(repaint: time);

  final ValueListenable<double> time;
  final ui.FragmentShader? shader;
  final ui.Image? texture;
  final bool economy;

  static final _stars = List.generate(240, _Star.new);
  static const _space = Color(0xFF020609);
  static const _revolution = 45.5;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = _space);
    // Planet geometry from the mockup: far below the bottom edge, so only
    // its upper limb shows.
    final c = Offset(w * 0.38, h * 1.39);
    final r = math.max(w * 0.88, h * 0.84);

    _starsLayer(canvas, size, t);
    _earth(canvas, c, r, t);
    _surfaceWaves(canvas, c, r, t);
    _atmosphere(canvas, size, c, r, t);
    _ribbons(canvas, c, r, t);
  }

  void _starsLayer(Canvas canvas, Size size, double t) {
    final w = size.width, h = size.height;
    final n = economy ? 95 : 240;
    final angle = 0.035 * math.sin(t * 0.12);
    final ca = math.cos(angle), sa = math.sin(angle);
    final cx = w * 0.52, cy = h * 0.45;
    final dot = Paint();
    for (var i = 0; i < n; i++) {
      final p = _stars[i];
      final depth = 0.2 + p.z;
      final drift = t * 0.013 * depth;
      final x0 = (p.u - 0.52) * w, y0 = (p.v - 0.45) * h;
      final x = ((cx + x0 * ca - y0 * sa - drift * w) % w + w) % w;
      final y =
          ((cy + x0 * sa + y0 * ca + math.sin(t * 0.19) * h * 0.013 * depth) %
                      h +
                  h) %
              h;
      final alpha = 0.22 + 0.42 * (0.5 + 0.5 * math.sin(t * 0.7 + i * 1.31));
      dot.color =
          (i % 7 == 0 ? const Color(0xFFA1EAF7) : const Color(0xFFDAE8F3))
              .withValues(alpha: alpha);
      final o = Offset(x, y);
      canvas.drawCircle(o, p.r * (0.8 + p.z * 0.4), dot);
      if (i % 19 == 0) {
        canvas.drawCircle(
          o,
          6,
          Paint()
            ..shader = ui.Gradient.radial(
                o, 6, const [Color(0x55C7FAFF), Color(0x00B5F0FF)]),
        );
      }
    }
  }

  void _earth(Canvas canvas, Offset c, double r, double t) {
    final disc = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final sh = shader;
    final tex = texture;
    canvas.save();
    canvas.clipPath(disc);
    var ready = sh != null && tex != null && !SphereAssets.broken;
    if (ready) {
      try {
        // In natural mode the shader draws its disc at 0.98 of half the rect.
        final side = 2 * r / 0.98;
        sh
          ..setFloat(0, side)
          ..setFloat(1, side)
          ..setFloat(2, t)
          ..setFloat(3, t * 2 * math.pi / _revolution)
          ..setFloat(4, 0)
          ..setFloat(5, 0)
          ..setFloat(6, 1)
          ..setFloat(7, 0)
          ..setImageSampler(0, tex, filterQuality: FilterQuality.low);
      } catch (_) {
        // This GPU/driver can't run it: the stand-in from now on.
        SphereAssets.broken = true;
        ready = false;
      }
    }
    if (!ready) {
      // Gradient stand-in until (or if) the shader is available.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.9),
            radius: 1.2,
            colors: const [
              Color(0xFF2A5470),
              Color(0xFF0D2233),
              Color(0xFF040B12),
            ],
            stops: const [0, 0.35, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    } else {
      final side = 2 * r / 0.98;
      canvas.translate(c.dx - side / 2, c.dy - side / 2);
      canvas.drawRect(Rect.fromLTWH(0, 0, side, side), Paint()..shader = sh);
    }
    canvas.restore();
  }

  /// Cold currents on the front hemisphere near the visible limb: lines
  /// whose latitude waves along longitude and time.
  void _surfaceWaves(Canvas canvas, Offset c, double r, double t) {
    final bands = economy ? 4 : 9;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var b = 0; b < bands; b++) {
      final path = Path();
      for (var i = 0; i <= 100; i++) {
        final lon = -math.pi / 2 + i / 100 * math.pi;
        final lat = 0.76 +
            b * 0.026 +
            math.sin(lon * 3 - t * 0.65 + b * 0.11) * 0.12 +
            math.sin(lon * 7 + t * 0.37) * 0.025;
        final x = math.cos(lat) * math.sin(lon), y = math.sin(lat);
        final sx = c.dx + x * r, sy = c.dy - y * r;
        i == 0 ? path.moveTo(sx, sy) : path.lineTo(sx, sy);
      }
      if (b == 0 && !economy) {
        canvas.drawPath(
          path,
          stroke
            ..strokeWidth = 3
            ..color = const Color(0x5935E7FF)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
        );
        stroke.maskFilter = null;
      }
      canvas.drawPath(
        path,
        stroke
          ..strokeWidth = b == 0 ? 0.95 : 0.45
          ..color = Color.fromRGBO(115, 244, 255, 0.14 * (1 - b / bands)),
      );
    }
  }

  void _atmosphere(Canvas canvas, Size size, Offset c, double r, double t) {
    final outer = r * 1.065;
    canvas.drawCircle(
      c,
      outer,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0x002CDAFF),
            const Color(0x002CDAFF),
            const Color(0xFF2CDAFF)
                .withValues(alpha: 0.48 + 0.06 * math.sin(t * 0.7)),
            const Color(0xFF2CDAFF).withValues(alpha: 0.17),
            const Color(0x002CDAFF),
          ],
          stops: const [0, 0.906, 0.9315, 0.9465, 1],
        ).createShader(Rect.fromCircle(center: c, radius: outer)),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = const Color(0xB0B6F7FF),
    );
  }

  /// One vertex of orbit [band] at angle [a] — the same model as the
  /// connect core's orbits, in the sign-in proportions (wider, flatter).
  _Pt _point(double a, int band, double t, Offset c, double r) {
    final radius = r * (1.19 + band * 0.012);
    final rip = 1 +
        math.sin(a * 4 - t * 0.9 + band * 0.24) * 0.025 +
        math.sin(a * 7 + t * 0.55 + band * 0.4) * 0.012;
    final x = math.cos(a) * radius * rip;
    final y = math.sin(a) * radius * rip;
    final z = math.sin(a * 3 - t * 0.44 + band * 0.3) * radius * 0.025;
    const tilt = 0.34;
    final ny = y * math.cos(tilt) - z * math.sin(tilt);
    final nz = y * math.sin(tilt) + z * math.cos(tilt);
    final turn = -0.58 + math.sin(t * 0.16) * 0.13;
    return _Pt(
      c.dx + x * math.cos(turn) - ny * math.sin(turn),
      c.dy + x * math.sin(turn) + ny * math.cos(turn),
      nz,
    );
  }

  bool _behind(_Pt p, Offset c, double r) {
    final nx = (p.x - c.dx) / r, ny = (p.y - c.dy) / r;
    final d2 = nx * nx + ny * ny;
    return d2 < 1 && p.z < math.sqrt(1 - d2) * r;
  }

  /// Front halves of the orbit band and its particles. (The far halves
  /// fall inside the opaque disc and would be covered anyway.)
  void _ribbons(Canvas canvas, Offset c, double r, double t) {
    final bands = economy ? 8 : 18;
    final vertices = economy ? 120 : 210;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var b = bands - 1; b >= 0; b--) {
      final path = Path();
      var drawing = false;
      for (var i = 0; i <= vertices; i++) {
        final a = i / vertices * math.pi * 2;
        final p = _point(a, b, t, c, r);
        if (_behind(p, c, r)) {
          drawing = false;
          continue;
        }
        if (!drawing) {
          path.moveTo(p.x, p.y);
          drawing = true;
        } else {
          path.lineTo(p.x, p.y);
        }
      }
      if (b == 0 && !economy) {
        canvas.drawPath(
          path,
          stroke
            ..strokeWidth = 4
            ..color = const Color(0x5945E9FF)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        stroke.maskFilter = null;
      }
      canvas.drawPath(
        path,
        stroke
          ..strokeWidth = b == 0 ? 1.5 : 0.55
          ..color =
              Color.fromRGBO(133, 235, 249, 0.34 * (1 - b / (bands * 1.15))),
      );
    }

    final count = economy ? 28 : 78;
    final dot = Paint()..color = const Color(0xA6C4FAFF);
    final glow = Paint()
      ..color = const Color(0x8060E5FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    for (var i = 0; i < count; i++) {
      final a = (i * 2.399 + t * 0.32) % (math.pi * 2);
      final p = _point(a, i % 7 + 1, t, c, r);
      if (_behind(p, c, r)) continue;
      final big = i % 13 == 0;
      final size = (big ? 1.8 : 0.7) * (1 + p.z / r * 0.25);
      final o = Offset(p.x, p.y);
      if (big && !economy) canvas.drawCircle(o, size * 3, glow);
      canvas.drawCircle(o, size, dot);
    }
  }

  @override
  bool shouldRepaint(_EarthPainter old) =>
      old.shader != shader ||
      old.texture != texture ||
      old.economy != economy ||
      old.time != time;
}
