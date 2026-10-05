import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/wb_colors.dart';
import '../immersive/star_field.dart';
import '../immersive/tinted_glass.dart';
import '../immersive/wave_field.dart';
import 'wave_params.dart';

/// Screen background. Since V5 every screen that uses it gets the
/// immersive wave field (crimson streams with depth, leaning towards the
/// selected location's flag [tint]) plus a soft tinted glow — same API as
/// before, so all secondary screens follow the new look.
class OceanBackground extends ConsumerWidget {
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
    this.stars = false,
  });

  /// Vector star field over the waves (sign-in screens).
  final bool stars;

  final Widget child;
  final bool illuminate;
  final bool animateWaves;

  /// The selected location's flag accent (or null).
  final Color? tint;

  /// Kept for API compatibility: liveliness now comes from the shared
  /// immersive clock; amplitude maps to the field's intensity.
  final double waveSpeed;
  final double waveAmplitude;
  final int waveLineCount;

  /// Caps how wide the content column ever grows — keeps the mobile layout
  /// centered and readable on a big desktop window.
  final double maxContentWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No explicit tint: follow the selected location like the rest of the app.
    final tint = this.tint ?? ref.watch(appWaveParamsProvider).tint;
    return ColoredBox(
      color: WbColors.midnight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (animateWaves)
            Positioned.fill(
              child: WaveField(
                tint: tint,
                layers: 18,
                intensity:
                    (0.45 + 0.25 * (waveAmplitude - 0.9)).clamp(0.3, 1.0),
              ),
            ),
          if (stars) const Positioned.fill(child: StarField()),
          if (tint != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.6),
                      radius: 1.2,
                      colors: [
                        tint.withValues(alpha: illuminate ? 0.10 : 0.06),
                        tint.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              // One shared blur pass for all glass cards on this screen
              // (TintedGlass uses BackdropFilter.grouped).
              child: GlassGroup(child: child),
            ),
          ),
        ],
      ),
    );
  }
}
