import '../../core/theme/wb_theme.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/wb_colors.dart';
import '../immersive/immersive_clock.dart';
import 'traffic_format.dart';

/// A liquid-fill bar for subscription traffic — the level (and its color)
/// tracks [usedBytes] / [limitBytes], with a slow animated wave riding the
/// fill line instead of a static progress rect. Replaces a plain "12.4 GB /
/// 100 GB" text line, which read as an afterthought next to the rest of
/// Home's animated, wave-themed chrome.
///
/// Driven by the shared [ImmersiveClock] (~30 fps, frozen with reduced
/// motion) — its own repeating controller used to keep Home rendering at
/// the full display rate.
class TrafficWaveBar extends StatelessWidget {
  const TrafficWaveBar({
    super.key,
    required this.usedBytes,
    required this.limitBytes,
    required this.s,
  });

  final int usedBytes;
  final int? limitBytes;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final limit = limitBytes;
    // Unlimited plans have nothing to fill *against* — a small, steady
    // band instead of a 0%/100% guess, since neither would mean anything.
    final fraction = (limit == null || limit <= 0)
        ? null
        : (usedBytes / limit).clamp(0.0, 1.0);
    // Low usage reads as calm cyan, climbing usage warms toward amber and
    // then red as the limit actually gets close — the same "how worried
    // should I be" read as a fuel gauge, at a glance, without reading the
    // numbers first.
    final color = fraction == null
        ? context.accent
        : Color.lerp(
            context.accent,
            Color.lerp(WbColors.warning, WbColors.error, ((fraction - 0.7) / 0.3).clamp(0.0, 1.0))!,
            (fraction / 0.7).clamp(0.0, 1.0),
          )!;
    final label = formatTraffic(usedBytes, limit, s);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 40,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: WbColors.ice08),
            RepaintBoundary(
              child: CustomPaint(
                painter: _WaveFillPainter(
                  fraction: fraction ?? 0.16,
                  time: ImmersiveClock.of(context),
                  color: color,
                  steady: fraction == null,
                ),
                size: Size.infinite,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: WbColors.ice,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveFillPainter extends CustomPainter {
  _WaveFillPainter({
    required this.fraction,
    required this.time,
    required this.color,
    required this.steady,
  }) : super(repaint: time);

  final double fraction;

  /// Seconds; one wave cycle per 6 s (continuous — no jump at a loop).
  final ValueListenable<double> time;
  final Color color;
  final bool steady;

  @override
  void paint(Canvas canvas, Size size) {
    final level = size.height * (1 - fraction);
    final waveHeight = steady ? 2.5 : 3.5;
    final phase = time.value / 6 * math.pi * 2;

    final path = Path()..moveTo(0, size.height);
    const steps = 40;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = size.width * t;
      final y = level +
          math.sin(t * math.pi * 4 + phase) * waveHeight +
          math.sin(t * math.pi * 2.3 - phase * 1.4) * waveHeight * 0.5;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.85)],
    );
    final paint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, paint);

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final linePath = Path();
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = size.width * t;
      final y = level +
          math.sin(t * math.pi * 4 + phase) * waveHeight +
          math.sin(t * math.pi * 2.3 - phase * 1.4) * waveHeight * 0.5;
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _WaveFillPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.time != time ||
      oldDelegate.color != color;
}
