import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// The connect core's orbit model for one frame: every orbit vertex and
/// particle, computed once and shared by the far pass (seen through the
/// glass) and the near pass. Each orbit is a ring around the sphere,
/// rippled by two sines, lifted in z by a third, tilted and slowly swaying.
///
/// Per vertex only multiply-adds: the sines of the vertex angle come from
/// a table per vertex count, the per-band and per-frame phases are folded
/// in with the angle-addition identity (sin(ka + p) = sin ka·cos p +
/// cos ka·sin p). Same numbers as evaluating the model directly (see
/// [point] and test/orbit_frame_test.dart), several times fewer sin/cos.
class OrbitFrame {
  OrbitFrame(this.bands)
      : _c4 = Float64List(bands),
        _s4 = Float64List(bands),
        _c7 = Float64List(bands),
        _s7 = Float64List(bands),
        _c3 = Float64List(bands),
        _s3 = Float64List(bands);

  final int bands;

  static const tilt = 0.86;
  static final _cosTilt = math.cos(tilt);
  static final _sinTilt = math.sin(tilt);

  // Per-frame state.
  double _cx = 0, _cy = 0, _rs = 1, _shrink = 1, _cosTurn = 1, _sinTurn = 0;
  final Float64List _c4, _s4, _c7, _s7, _c3, _s3;

  /// Vertex positions of all bands (band-major, [vertexCount] + 1 each:
  /// the ring is closed) and whether each vertex is hidden by the sphere.
  Float64List xs = Float64List(0), ys = Float64List(0);
  Uint8List behind = Uint8List(0);
  int vertexCount = 0;

  /// Particle positions, depth and visibility, filled by [fillParticles].
  Float64List px = Float64List(0), py = Float64List(0), pz = Float64List(0);
  Uint8List pBehind = Uint8List(0);

  /// The last point from [point].
  double x = 0, y = 0, z = 0;

  void setFrame({
    required double t,
    required Offset center,
    required double rs,
    required double charge,
  }) {
    _cx = center.dx;
    _cy = center.dy;
    _rs = rs;
    // While connecting the orbits draw in across their long axis.
    _shrink = 1 - 0.12 * charge;
    final turn = -0.38 + math.sin(t * 0.16) * 0.13;
    _cosTurn = math.cos(turn);
    _sinTurn = math.sin(turn);
    for (var b = 0; b < bands; b++) {
      final p4 = -t * 0.9 + b * 0.24;
      final p7 = t * 0.55 + b * 0.4;
      final p3 = -t * 0.44 + b * 0.3;
      _c4[b] = math.cos(p4);
      _s4[b] = math.sin(p4);
      _c7[b] = math.cos(p7);
      _s7[b] = math.sin(p7);
      _c3[b] = math.cos(p3);
      _s3[b] = math.sin(p3);
    }
  }

  /// One point of orbit [band] at angle [a], into [x], [y], [z].
  void point(double a, int band) {
    _place(
      band,
      math.cos(a),
      math.sin(a),
      math.sin(a * 4) * _c4[band] + math.cos(a * 4) * _s4[band],
      math.sin(a * 7) * _c7[band] + math.cos(a * 7) * _s7[band],
      math.sin(a * 3) * _c3[band] + math.cos(a * 3) * _s3[band],
    );
  }

  void _place(int band, double ca, double sa, double s4, double s7, double s3) {
    final radius = _rs * (1.08 + band * 0.026);
    final rr = radius * (1 + s4 * 0.025 + s7 * 0.012);
    final px = ca * rr * _shrink;
    final py = sa * rr;
    final pz = s3 * radius * 0.025;
    final ny = py * _cosTilt - pz * _sinTilt;
    z = py * _sinTilt + pz * _cosTilt;
    x = _cx + px * _cosTurn - ny * _sinTurn;
    y = _cy + px * _sinTurn + ny * _cosTurn;
  }

  /// Whether the last [point] is hidden behind the sphere.
  bool get isBehind {
    final nx = (x - _cx) / _rs, ny = (y - _cy) / _rs;
    final d2 = nx * nx + ny * ny;
    return d2 < 1 && z < math.sqrt(1 - d2) * _rs;
  }

  /// All vertices of all bands, [vertices] segments per ring.
  void fillBands(int vertices) {
    final n = vertices + 1;
    if (xs.length != bands * n) {
      xs = Float64List(bands * n);
      ys = Float64List(bands * n);
      behind = Uint8List(bands * n);
    }
    vertexCount = vertices;
    final tb = _RingTable.of(vertices);
    for (var b = 0; b < bands; b++) {
      final c4 = _c4[b], s4 = _s4[b], c7 = _c7[b], s7 = _s7[b];
      final c3 = _c3[b], s3 = _s3[b];
      final o = b * n;
      for (var i = 0; i < n; i++) {
        _place(
          b,
          tb.c1[i],
          tb.s1[i],
          tb.s4[i] * c4 + tb.c4[i] * s4,
          tb.s7[i] * c7 + tb.c7[i] * s7,
          tb.s3[i] * c3 + tb.c3[i] * s3,
        );
        xs[o + i] = x;
        ys[o + i] = y;
        behind[o + i] = isBehind ? 1 : 0;
      }
    }
  }

  /// [count] particles: particle i rides band (i % 7) + 1 at angle
  /// i · 2.399 + [angle] (golden-angle spread).
  void fillParticles(int count, double angle) {
    if (px.length != count) {
      px = Float64List(count);
      py = Float64List(count);
      pz = Float64List(count);
      pBehind = Uint8List(count);
    }
    for (var i = 0; i < count; i++) {
      point((i * 2.399 + angle) % (math.pi * 2), i % 7 + 1);
      px[i] = x;
      py[i] = y;
      pz[i] = z;
      pBehind[i] = isBehind ? 1 : 0;
    }
  }
}

/// sin/cos of a, 3a, 4a, 7a at a = i / n · 2π, i = 0..n.
class _RingTable {
  _RingTable(int n)
      : c1 = Float64List(n + 1),
        s1 = Float64List(n + 1),
        c3 = Float64List(n + 1),
        s3 = Float64List(n + 1),
        c4 = Float64List(n + 1),
        s4 = Float64List(n + 1),
        c7 = Float64List(n + 1),
        s7 = Float64List(n + 1) {
    for (var i = 0; i <= n; i++) {
      final a = i / n * math.pi * 2;
      c1[i] = math.cos(a);
      s1[i] = math.sin(a);
      c3[i] = math.cos(a * 3);
      s3[i] = math.sin(a * 3);
      c4[i] = math.cos(a * 4);
      s4[i] = math.sin(a * 4);
      c7[i] = math.cos(a * 7);
      s7[i] = math.sin(a * 7);
    }
  }

  final Float64List c1, s1, c3, s3, c4, s4, c7, s7;

  static final _cache = <int, _RingTable>{};
  static _RingTable of(int n) => _cache[n] ??= _RingTable(n);
}
