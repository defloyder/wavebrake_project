import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../immersive/immersive_colors.dart';

/// What the tunnel is showing.
enum TunnelPhase { idle, latency, download, upload, done, failed }

/// "Wave tunnel" — the speed-test scene. A perspective tunnel of deformed
/// wave rings receding into depth, with light streaks running along its
/// walls:
/// - download: rings and streaks flow towards the viewer (arctic);
/// - upload: they flow away into the depth (crimson);
/// - latency: the rings breathe in place, a pulse per probe;
/// - idle / done: slow drift; failed: amber, still.
/// Flow speed, ring deformation and streak length follow the measured
/// throughput ([mbps], already eased by the caller), on a log scale so
/// 5 and 500 Mbps both read. [progress] (0..1) draws the phase arc on the
/// rim. Pure decoration — the numbers are shown by the screen.
class WaveTunnelPainter extends CustomPainter {
  WaveTunnelPainter({
    required this.time,
    required this.phase,
    required this.mbps,
    required this.progress,
  }) : super(repaint: time);

  final ValueListenable<double> time;
  final TunnelPhase phase;
  final double mbps;
  final double progress;

  static const _rings = 18;
  static const _streaks = 64;

  Color get _color => switch (phase) {
        TunnelPhase.upload => Ic.crimson,
        TunnelPhase.failed => Ic.amber,
        TunnelPhase.latency => const Color(0xFFBFEFEA),
        _ => Ic.arctic,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final c = size.center(Offset.zero);
    final rim = size.shortestSide * 0.47;
    final color = _color;

    // Energy 0..1 from throughput (log scale up to ~600 Mbps).
    final energy = (math.log(1 + mbps) / math.log(601)).clamp(0.0, 1.0);
    final running = phase == TunnelPhase.download ||
        phase == TunnelPhase.upload ||
        phase == TunnelPhase.latency;
    final dir = switch (phase) {
      TunnelPhase.download => 1.0,
      TunnelPhase.upload => -1.0,
      TunnelPhase.failed => 0.0,
      _ => 0.25,
    };
    final speed = 0.035 + 0.55 * energy;
    final flow = t * speed * dir;

    // Depth haze behind the tunnel.
    canvas.drawCircle(
      c,
      rim * 1.02,
      Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: 0.10 + 0.12 * energy),
          Ic.background.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: rim * 1.02)),
    );

    // Rings: z in 0 (far) .. 1 (near); perspective scale.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final rings = <(double, Path, double)>[];
    for (var i = 0; i < _rings; i++) {
      final z = (i / _rings + flow) % 1.0;
      final zz = z < 0 ? z + 1 : z;
      final scale = 0.10 + 0.90 * math.pow(zz, 1.8);
      final breathe = phase == TunnelPhase.latency
          ? 1 + 0.06 * math.sin(t * 4.2 - zz * 6)
          : 1.0;
      final r = rim * scale * breathe;
      // Gentle deformation: rings must still read as a tunnel, the wave is
      // a ripple on them, stronger the faster the data flows.
      final amp = 0.012 + 0.045 * energy * (0.4 + 0.6 * zz);
      final k = 2 + (i % 2);
      // A slow swirl moves the far rings off-centre: the tunnel bends.
      final swirl = Offset(
        math.sin(t * 0.35 + zz * 2.6) * rim * 0.10 * (1 - zz),
        math.cos(t * 0.28 + zz * 2.1) * rim * 0.07 * (1 - zz),
      );
      final path = Path();
      const seg = 72;
      for (var j = 0; j <= seg; j++) {
        final th = j / seg * 2 * math.pi;
        final rr = r *
            (1 +
                amp * math.sin(k * th + t * (0.8 + energy * 2.2) + i * 0.7) +
                amp * 0.35 * math.sin((k + 3) * th - t * 0.6 + i));
        final p = c + swirl + Offset(math.cos(th) * rr, math.sin(th) * rr);
        j == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      rings.add((zz, path, r));
    }
    rings.sort((a, b) => a.$1.compareTo(b.$1)); // far first
    for (final (z, path, _) in rings) {
      final fade = math.sin(z * math.pi).clamp(0.0, 1.0); // fade at both ends
      ringPaint
        ..strokeWidth = 0.6 + 1.6 * z
        ..color = color.withValues(
            alpha: (0.10 + 0.55 * fade) * (0.6 + 0.4 * energy));
      canvas.drawPath(path, ringPaint);
      if (z > 0.72 && fade > 0.3) {
        ringPaint
          ..strokeWidth = 5
          ..color = color.withValues(alpha: 0.07 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawPath(path, ringPaint);
        ringPaint.maskFilter = null;
      }
    }

    // Light streaks along the tunnel walls.
    final streak = Paint()..strokeCap = StrokeCap.round;
    final rnd = math.Random(7);
    for (var i = 0; i < _streaks; i++) {
      final angle = rnd.nextDouble() * 2 * math.pi;
      final offset = rnd.nextDouble();
      final speedMul = 0.7 + rnd.nextDouble() * 0.6;
      final z0 = ((offset + flow * 1.6 * speedMul) % 1.0 + 1) % 1.0;
      final len = (0.04 + 0.16 * energy) * (dir == 0 ? 0.3 : 1);
      final z1 = (z0 - len * dir.sign).clamp(0.0, 1.0);
      Offset at(double z) {
        final s = 0.10 + 0.90 * math.pow(z, 1.8);
        final r = rim * s * (0.92 + 0.06 * math.sin(angle * 5 + t));
        return c + Offset(math.cos(angle) * r, math.sin(angle) * r);
      }

      final fade = math.sin(z0 * math.pi);
      streak
        ..strokeWidth = 0.8 + 1.8 * z0
        ..color = (i % 9 == 0 ? Colors.white : color)
            .withValues(alpha: (0.15 + 0.6 * energy) * fade);
      canvas.drawLine(at(z1), at(z0), streak);
    }

    // Calm centre so the number reads.
    canvas.drawCircle(
      c,
      rim * 0.42,
      Paint()
        ..shader = RadialGradient(colors: [
          Ic.background.withValues(alpha: 0.85),
          Ic.background.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: rim * 0.42)),
    );

    // Rim: track + phase progress arc.
    final rect = Rect.fromCircle(center: c, radius: rim);
    canvas.drawCircle(
        c,
        rim,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Ic.glassBorder.withValues(alpha: 0.5));
    if (running && progress > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + 2 * math.pi * progress,
          colors: [color.withValues(alpha: 0.3), color],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect);
      canvas.drawArc(
          rect, -math.pi / 2, 2 * math.pi * progress.clamp(0, 1), false, arc);
      canvas.drawArc(
          rect,
          -math.pi / 2,
          2 * math.pi * progress.clamp(0, 1),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..color = color.withValues(alpha: 0.12)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
  }

  @override
  bool shouldRepaint(WaveTunnelPainter old) =>
      old.phase != phase ||
      old.mbps != mbps ||
      old.progress != progress ||
      old.time != time;
}
