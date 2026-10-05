import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'effects_quality.dart';
import 'immersive_clock.dart';
import 'immersive_colors.dart';

/// Full-screen background: two families of broad waves (deep crimson
/// streams with a brighter crest, and a much fainter arctic reflection)
/// across the lower two thirds of the screen. Pure decoration: no hit
/// testing, no semantics, sits under the content.
class WaveField extends ConsumerWidget {
  const WaveField(
      {super.key, this.intensity = 1.0, this.layers = 26, this.tint});

  /// 0..1 — brighter while connected.
  final double intensity;
  final int layers;

  /// Location flag accent: the crimson streams lean towards it a little
  /// (the same flag-tinted mood the rest of the app follows).
  final Color? tint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Economy effects (older phones): at most 12 layers, as in the spec.
    final economy = ref.watch(effectsEconomyProvider);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _WaveFieldPainter(
              time: ImmersiveClock.of(context),
              intensity: intensity,
              layers: economy ? (layers < 12 ? layers : 12) : layers,
              tint: tint,
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveFieldPainter extends CustomPainter {
  _WaveFieldPainter(
      {required this.time,
      required this.intensity,
      required this.layers,
      this.tint})
      : super(repaint: time);

  final ValueListenable<double> time;
  final double intensity;
  final int layers;
  final Color? tint;

  /// The designed crimson recolored to the flag accent's hue (keeps its
  /// depth and saturation, so a blue flag gives deep blue waves, not a
  /// crimson/blue mix). A near-grey accent leaves the crimson as is.
  Color _tinted(Color c) {
    final t = tint;
    if (t == null) return c;
    final hsl = HSLColor.fromColor(t);
    if (hsl.saturation < 0.15) return c;
    final base = HSLColor.fromColor(c);
    return base.withHue(hsl.hue).withAlpha(base.alpha).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = Ic.background);

    // Soft burgundy depth behind everything.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.3, 0.55),
          radius: 1.1,
          colors: [
            _tinted(Ic.burgundy).withValues(alpha: 0.55),
            Ic.background.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );

    const step = 6.0;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..style = PaintingStyle.fill;

    // Arctic reflection: a few faint lines high up, drifting the other way.
    for (var i = 0; i < 4; i++) {
      final base = h * (0.30 + i * 0.035);
      final amp = h * 0.025;
      final path = Path();
      for (double x = 0; x <= w + step; x += step) {
        final y = base +
            amp * math.sin(x / w * 2.4 * math.pi - t * 0.20 + i * 0.6) +
            amp * 0.4 * math.sin(x / w * 5.1 * math.pi + t * 0.13 + i);
        x == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      stroke
        ..strokeWidth = 0.7
        ..color = Ic.arctic.withValues(alpha: 0.045 + 0.02 * intensity);
      canvas.drawPath(path, stroke);
    }

    // Crimson streams, far (thin, dark) to near (brighter crest).
    for (var i = 0; i < layers; i++) {
      final k = i / (layers - 1); // 0 far .. 1 near
      final base = h * (0.42 + 0.50 * k);
      final amp = h * (0.035 + 0.05 * (1 - k));
      final f1 = 1.6 + 0.9 * k;
      final f2 = 3.7 - 1.1 * k;
      final phase = i * 0.37;
      final crest = Path();
      for (double x = 0; x <= w + step; x += step) {
        final u = x / w;
        final y = base +
            amp * math.sin(u * f1 * math.pi + t * 0.32 + phase) +
            amp *
                0.45 *
                math.sin(u * f2 * math.pi - t * 0.32 * 0.7 + phase * 1.7);
        x == 0 ? crest.moveTo(x, y) : crest.lineTo(x, y);
      }
      // Faint volume under the nearer crests.
      if (k > 0.55) {
        final body = Path.from(crest)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
        fill.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _tinted(Ic.crimson)
                .withValues(alpha: 0.035 * k * (0.6 + 0.4 * intensity)),
            Ic.background.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, base - amp * 1.5, w, h - base));
        canvas.drawPath(body, fill);
      }
      final bright = i == layers - 3 || i == layers - 9;
      stroke
        ..strokeWidth = bright ? 1.4 : 0.5 + 0.6 * k
        ..color = _tinted(Color.lerp(Ic.burgundy, Ic.crimson, k * k)!)
            .withValues(
                alpha: (bright ? 0.55 : 0.10 + 0.22 * k) *
                    (0.7 + 0.3 * intensity));
      canvas.drawPath(crest, stroke);
      if (bright) {
        stroke
          ..strokeWidth = 6
          ..color = _tinted(Ic.crimson)
              .withValues(alpha: 0.06 * (0.6 + 0.4 * intensity))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawPath(crest, stroke);
        stroke.maskFilter = null;
      }
    }
  }

  @override
  bool shouldRepaint(_WaveFieldPainter old) =>
      old.intensity != intensity ||
      old.layers != layers ||
      old.time != time ||
      old.tint != tint;
}
