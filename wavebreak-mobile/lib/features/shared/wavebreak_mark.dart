import 'package:flutter/material.dart';

import '../../core/theme/wb_colors.dart';

/// The WAVEBREAK emblem — a square, transparent-background crop of the
/// brand mark (assets/branding/wavebreak_mark_square.png), sized so it
/// drops cleanly into compact UI spots (connect button, drawer icon).
class WavebreakMark extends StatelessWidget {
  const WavebreakMark({
    super.key,
    this.size = 72,
    this.glow = false,
  });

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      'assets/branding/wavebreak_mark_square.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
    if (!glow) return mark;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: WbColors.waveCyan.withValues(alpha: 0.28),
            blurRadius: 24,
          ),
        ],
      ),
      child: mark,
    );
  }
}

/// The WAVEBREAK wordmark crop (assets/branding/wavebreak_wordmark.png).
/// [size] sets the rendered height; width follows the source aspect ratio.
class WavebreakWordmark extends StatelessWidget {
  const WavebreakWordmark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/wavebreak_wordmark.png',
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// A plain-text "WAVEBREAK" label for tight spots (a header row flanked by
/// icons, the drawer title) where the wordmark image's fixed aspect ratio
/// would overflow a narrow, space-constrained row.
class WavebreakWordmarkText extends StatelessWidget {
  const WavebreakWordmarkText({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      'WAVEBREAK',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: 2.4,
        color: WbColors.ice,
      ),
    );
  }
}
