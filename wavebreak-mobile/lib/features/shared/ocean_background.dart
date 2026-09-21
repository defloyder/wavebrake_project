import 'package:flutter/material.dart';

import '../../core/theme/wb_colors.dart';
import 'animated_waves.dart';

class OceanBackground extends StatelessWidget {
  const OceanBackground({
    super.key,
    required this.child,
    this.illuminate = false,
    this.animateWaves = true,
    this.tint,
    this.waveSpeed = 1.0,
    this.waveAmplitude = 1.0,
    this.waveLineCount = 4,
    this.maxContentWidth = 560,
  });

  final Widget child;
  final bool illuminate;
  final bool animateWaves;

  /// Subtle accent for the ambient glow — e.g. the selected location's flag
  /// color. Kept low-opacity so it never overwhelms the brand background.
  final Color? tint;

  /// Multipliers so callers can tie wave liveliness to app state (e.g.
  /// faster/bigger while connected) without ever feeling frantic.
  final double waveSpeed;
  final double waveAmplitude;
  final int waveLineCount;

  /// Caps how wide the content column ever grows — keeps the mobile layout
  /// centered and readable on a big desktop window instead of stretching
  /// edge to edge. Screens with their own desktop-specific layout (e.g. a
  /// two-column Home) pass a larger value.
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final resolvedTint = tint ?? WbColors.waveCyan;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        color: WbColors.midnight,
        // radius is a fraction of the box's SHORTEST side, so on a wide,
        // short desktop window a small radius traces a visible circle that
        // terminates well inside the frame — a "spotlight in a dark void"
        // look (reported as a black hole in the background). Using a much
        // bigger radius keeps the whole visible area inside the gradient's
        // smooth falloff, however wide the window gets, so it reads as one
        // continuous wash instead of a bounded shape.
        gradient: illuminate
            ? RadialGradient(
                center: const Alignment(0, -0.05),
                radius: 1.8,
                colors: [
                  resolvedTint.withValues(alpha: 0.13),
                  resolvedTint.withValues(alpha: 0.04),
                  WbColors.midnight,
                ],
                stops: const [0, 0.55, 1],
              )
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (animateWaves)
            Positioned.fill(
              child: AnimatedWaves(
                tint: resolvedTint,
                speed: waveSpeed,
                amplitude: waveAmplitude,
                lineCount: waveLineCount,
              ),
            ),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
