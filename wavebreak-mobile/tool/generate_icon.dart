// Generates the WAVEBREAK app icon (brand book §82): #0B1020 background,
// a stylized W + wave in the cyan→teal brand gradient, no text.
// Pure-Dart raster (no Flutter engine), run with:
//   dart run tool/generate_icon.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _cyan = [0x00, 0xD6, 0xFF];
const _teal = [0x00, 0xB4, 0xC8];

void main() {
  const size = 1024;
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorUint8.rgb(0x0B, 0x10, 0x20));

  final wPoints = [
    (0.18, 0.28),
    (0.36, 0.74),
    (0.50, 0.46),
    (0.64, 0.74),
    (0.82, 0.28),
  ];
  _strokePath(
    image,
    wPoints.map((p) => p.$1).toList(),
    wPoints.map((p) => p.$2).toList(),
    size,
    thickness: size * 0.085,
  );

  const waveSteps = 48;
  final waveX = <double>[];
  final waveY = <double>[];
  for (var i = 0; i <= waveSteps; i++) {
    final t = i / waveSteps;
    waveX.add(0.24 + 0.52 * t);
    waveY.add(0.87 + 0.03 * math.sin(t * math.pi * 2));
  }
  _strokePath(image, waveX, waveY, size, thickness: size * 0.05);

  final bytes = img.encodePng(image);
  Directory('assets/icon').createSync(recursive: true);
  File('assets/icon/wavebreak_icon_1024.png').writeAsBytesSync(bytes);
  stdout.writeln('Wrote assets/icon/wavebreak_icon_1024.png');
}

/// Strokes a polyline by stamping filled circles along each segment, which
/// gives clean rounded joins/caps without the banding artifacts thick
/// antialiased lines produce in package:image.
void _strokePath(
  img.Image image,
  List<double> xs,
  List<double> ys,
  int size, {
  required double thickness,
}) {
  final radius = (thickness / 2).round();
  final step = math.max(1.0, thickness / 4);

  for (var i = 0; i < xs.length - 1; i++) {
    final x1 = xs[i] * size;
    final y1 = ys[i] * size;
    final x2 = xs[i + 1] * size;
    final y2 = ys[i + 1] * size;
    final dx = x2 - x1;
    final dy = y2 - y1;
    final length = math.sqrt(dx * dx + dy * dy);
    final segments = math.max(1, (length / step).ceil());
    final overallT = i / (xs.length - 2 == 0 ? 1 : xs.length - 2);

    for (var s = 0; s <= segments; s++) {
      final t = s / segments;
      final px = x1 + dx * t;
      final py = y1 + dy * t;
      final color = img.ColorUint8.rgb(
        (_cyan[0] + (_teal[0] - _cyan[0]) * overallT).round(),
        (_cyan[1] + (_teal[1] - _cyan[1]) * overallT).round(),
        (_cyan[2] + (_teal[2] - _cyan[2]) * overallT).round(),
      );
      img.fillCircle(
        image,
        x: px.round(),
        y: py.round(),
        radius: radius,
        color: color,
        antialias: true,
      );
    }
  }
}
