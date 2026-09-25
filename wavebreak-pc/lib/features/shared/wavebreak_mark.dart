import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
///
/// Michroma — the exact font wavebreak-web uses for its own brand
/// wordmark (`.wb-brand-name { font-family: "Michroma", ... }`), loaded
/// via google_fonts (already a dependency) rather than bundling the
/// site's own woff2 file. Reserved for the wordmark specifically, same
/// as the site: this is a distinctive geometric display face, not a
/// general body/heading font (that's still Inter — see wb_theme.dart —
/// matching the site's own --font choice for everything else).
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
      style: GoogleFonts.michroma(
        fontSize: size,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.2,
        color: WbColors.ice,
      ),
    );
  }
}
