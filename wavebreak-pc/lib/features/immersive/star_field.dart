import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'immersive_clock.dart';
import 'immersive_colors.dart';

/// Vector stars on several depth planes (V5 sign-in scene): each with its
/// own radius, brightness and drift speed, a slow common camera turn and
/// soft twinkle — no flashes. Decoration only.
class StarField extends StatelessWidget {
  const StarField({super.key, this.count = 140});

  final int count;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _StarPainter(ImmersiveClock.of(context), count),
          ),
        ),
      ),
    );
  }
}

class _Star {
  _Star(math.Random r)
      : x = r.nextDouble(),
        y = r.nextDouble(),
        depth = r.nextDouble(),
        phase = r.nextDouble() * 2 * math.pi,
        teal = r.nextDouble() < 0.12;

  final double x, y, depth, phase;
  final bool teal;
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.time, this.count)
      : stars = List.generate(count, (_) => _Star(_rnd)),
        super(repaint: time);

  static final _rnd = math.Random(11);

  final ValueListenable<double> time;
  final int count;
  final List<_Star> stars;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final paint = Paint();
    final turn = math.sin(t * 0.02) * 0.04; // slow camera turn
    final c = size.center(Offset.zero);
    for (final s in stars) {
      final drift = (s.x + t * (0.002 + 0.006 * s.depth)) % 1.0;
      var p = Offset(drift * size.width, s.y * size.height * 0.85);
      final d = p - c;
      p = c +
          Offset(d.dx * math.cos(turn) - d.dy * math.sin(turn),
              d.dx * math.sin(turn) + d.dy * math.cos(turn));
      final twinkle = 0.75 + 0.25 * math.sin(t * (0.6 + s.depth) + s.phase);
      final radius = 0.4 + 1.3 * s.depth * s.depth;
      final alpha = (0.18 + 0.62 * s.depth) * twinkle;
      paint.color = (s.teal ? Ic.arctic : Ic.text).withValues(alpha: alpha);
      canvas.drawCircle(p, radius, paint);
      if (s.depth > 0.9) {
        paint.color =
            (s.teal ? Ic.arctic : Ic.text).withValues(alpha: alpha * 0.18);
        canvas.drawCircle(p, radius * 3.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.count != count;
}
