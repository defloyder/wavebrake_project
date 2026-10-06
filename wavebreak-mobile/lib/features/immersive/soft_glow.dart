import 'dart:math' as math;
import 'dart:ui';

/// Soft glows without a blur pass (P5). `MaskFilter.blur` renders the
/// shape into an offscreen texture and runs a Gaussian over it every frame
/// — the two blurred wave crests alone cost ~6 ms of GPU per frame on the
/// owner's phone. These draw the same falloff with a few plain strokes or
/// one radial gradient: a close look, no offscreen pass.

/// Peak opacity of a [width]-wide line blurred with [sigma] (as a fraction
/// of the line's own opacity).
double _peak(double width, double sigma) =>
    _erf(width / (2 * sigma * math.sqrt2));

/// Abramowitz–Stegun 7.1.26 (|error| < 1.5e-7).
double _erf(double x) {
  final t = 1 / (1 + 0.3275911 * x.abs());
  final y = 1 -
      (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                  0.284496736) *
              t +
          0.254829592) *
          t *
          math.exp(-x * x);
  return x >= 0 ? y : -y;
}

/// Three stacked strokes approximating `stroke(width) + blur(sigma)`.
List<(double, double)> _layers(double width, double sigma) {
  final p = _peak(width, sigma);
  return [
    (width + 4 * sigma, 0.30 * p),
    (width + 2 * sigma, 0.30 * p),
    (width, 0.42 * p),
  ];
}

/// [path] stroked [width] wide in [color], softened like a blur of [sigma].
void drawSoftPath(
    Canvas canvas, Path path, Color color, double width, double sigma) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  for (final (w, a) in _layers(width, sigma)) {
    canvas.drawPath(
        path,
        paint
          ..strokeWidth = w
          ..color = color.withValues(alpha: color.a * a));
  }
}

/// A ring of [width] at [radius], softened like a blur of [sigma].
void drawSoftRing(Canvas canvas, Offset center, double radius, Color color,
    double width, double sigma) {
  final paint = Paint()..style = PaintingStyle.stroke;
  for (final (w, a) in _layers(width, sigma)) {
    canvas.drawCircle(
        center,
        radius,
        paint
          ..strokeWidth = w
          ..color = color.withValues(alpha: color.a * a));
  }
}

/// The halo of a disc of [radius] with `BlurStyle.outer` and [sigma]:
/// half the color at the rim, Gaussian falloff outwards, nothing inside.
void drawOuterGlow(Canvas canvas, Offset center, double radius, Color color,
    double sigma) {
  final outer = radius + 3 * sigma;
  double at(double d) => (radius + d) / outer;
  Color c(double k) => color.withValues(alpha: color.a * k);
  canvas.drawCircle(
    center,
    outer,
    Paint()
      ..shader = Gradient.radial(
        center,
        outer,
        [
          c(0),
          c(0),
          c(0.5),
          c(0.5 * math.exp(-0.5)),
          c(0.5 * math.exp(-2)),
          c(0),
        ],
        [0, at(0), at(0), at(sigma), at(2 * sigma), 1],
      ),
  );
}
