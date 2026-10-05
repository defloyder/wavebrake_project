import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/features/immersive/orbit_frame.dart';

/// The orbit model evaluated directly, as the connect core did before the
/// per-frame tables (P5): the fast path must give the same points.
({double x, double y, double z}) reference(
    double a, int band, double t, Offset c, double rs, double charge) {
  final radius = rs * (1.08 + band * 0.026);
  final rip = 1 +
      math.sin(a * 4 - t * 0.9 + band * 0.24) * 0.025 +
      math.sin(a * 7 + t * 0.55 + band * 0.4) * 0.012;
  var x = math.cos(a) * radius * rip;
  final y = math.sin(a) * radius * rip;
  final z = math.sin(a * 3 - t * 0.44 + band * 0.3) * radius * 0.025;
  const tilt = 0.86;
  final ny = y * math.cos(tilt) - z * math.sin(tilt);
  final nz = y * math.sin(tilt) + z * math.cos(tilt);
  final turn = -0.38 + math.sin(t * 0.16) * 0.13;
  x *= 1 - 0.12 * charge;
  return (
    x: c.dx + x * math.cos(turn) - ny * math.sin(turn),
    y: c.dy + x * math.sin(turn) + ny * math.cos(turn),
    z: nz,
  );
}

bool referenceBehind(
    ({double x, double y, double z}) p, Offset c, double rs) {
  final nx = (p.x - c.dx) / rs, ny = (p.y - c.dy) / rs;
  final d2 = nx * nx + ny * ny;
  return d2 < 1 && p.z < math.sqrt(1 - d2) * rs;
}

void main() {
  const c = Offset(206, 160);
  const rs = 116.4;

  for (final t in [0.0, 1.7, 33.3, 1234.5]) {
    for (final charge in [0.0, 0.6]) {
      test('bands match the direct model (t=$t, charge=$charge)', () {
        final o = OrbitFrame(18)
          ..setFrame(t: t, center: c, rs: rs, charge: charge);
        for (final vertices in [84, 210]) {
          o.fillBands(vertices);
          var mismatchedSides = 0;
          for (var b = 0; b < 18; b++) {
            for (var i = 0; i <= vertices; i++) {
              final p = reference(
                  i / vertices * math.pi * 2, b, t, c, rs, charge);
              final k = b * (vertices + 1) + i;
              expect(o.xs[k], closeTo(p.x, 1e-6));
              expect(o.ys[k], closeTo(p.y, 1e-6));
              if ((o.behind[k] == 1) != referenceBehind(p, c, rs)) {
                mismatchedSides++; // only possible exactly on the rim
              }
            }
          }
          expect(mismatchedSides, lessThanOrEqualTo(1));
        }
      });
    }
  }

  test('particles match the direct model', () {
    const t = 12.5, angle = 4.2;
    final o = OrbitFrame(18)
      ..setFrame(t: t, center: c, rs: rs, charge: 0.3)
      ..fillParticles(78, angle);
    for (var i = 0; i < 78; i++) {
      final a = (i * 2.399 + angle) % (math.pi * 2);
      final p = reference(a, i % 7 + 1, t, c, rs, 0.3);
      expect(o.px[i], closeTo(p.x, 1e-6));
      expect(o.py[i], closeTo(p.y, 1e-6));
      expect(o.pz[i], closeTo(p.z, 1e-6));
    }
  });
}
