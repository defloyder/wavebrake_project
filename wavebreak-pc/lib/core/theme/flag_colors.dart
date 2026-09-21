import 'package:flutter/material.dart';

import 'wb_colors.dart';

/// Real, curated flag colors for locations we can realistically expect to
/// see (current + likely future server countries). Each entry is the
/// flag's actual palette (2-4 colors, in roughly the order they appear on
/// the flag) plus one accent — the flag's most vivid non-white/non-black
/// color, picked by hand as the color that reads best as a UI glow.
///
/// Anything NOT in this table (some exotic location a subscription adds
/// that we haven't curated yet) falls through to [_generatedPaletteFor],
/// which derives a *consistent, distinct* — but not necessarily
/// flag-accurate — color from the country code itself. So: yes, new
/// countries automatically get a color, but only entries in this table are
/// guaranteed to be the location's real flag colors. Adding a new country
/// here later is a one-line change.
const _curatedFlags = <String, ({List<Color> colors, Color accent})>{
  'TR': (colors: [Color(0xFFE30A17), Colors.white, Color(0xFFE30A17)], accent: Color(0xFFE30A17)),
  'NL': (colors: [Color(0xFFAE1C28), Colors.white, Color(0xFF21468B)], accent: Color(0xFF21468B)),
  'FI': (colors: [Color(0xFF002F6C), Colors.white, Color(0xFF002F6C)], accent: Color(0xFF002F6C)),
  'US': (colors: [Color(0xFFB22234), Colors.white, Color(0xFF3C3B6E)], accent: Color(0xFF3C3B6E)),
  'GB': (colors: [Color(0xFF012169), Colors.white, Color(0xFFC8102E)], accent: Color(0xFF012169)),
  'DE': (colors: [Color(0xFF000000), Color(0xFFDD0000), Color(0xFFFFCE00)], accent: Color(0xFFFFCE00)),
  'FR': (colors: [Color(0xFF0055A4), Colors.white, Color(0xFFEF4135)], accent: Color(0xFF0055A4)),
  'IT': (colors: [Color(0xFF009246), Colors.white, Color(0xFFCE2B37)], accent: Color(0xFF009246)),
  'ES': (colors: [Color(0xFFAA151B), Color(0xFFF1BF00), Color(0xFFAA151B)], accent: Color(0xFFF1BF00)),
  'PL': (colors: [Colors.white, Color(0xFFDC143C)], accent: Color(0xFFDC143C)),
  'SE': (colors: [Color(0xFF006AA7), Color(0xFFFECC02)], accent: Color(0xFFFECC02)),
  'NO': (colors: [Color(0xFFEF2B2D), Colors.white, Color(0xFF002868)], accent: Color(0xFFEF2B2D)),
  'CH': (colors: [Color(0xFFFF0000), Colors.white], accent: Color(0xFFFF0000)),
  'CA': (colors: [Color(0xFFFF0000), Colors.white], accent: Color(0xFFFF0000)),
  'JP': (colors: [Colors.white, Color(0xFFBC002D)], accent: Color(0xFFBC002D)),
  'SG': (colors: [Color(0xFFEF3340), Colors.white], accent: Color(0xFFEF3340)),
  'AU': (colors: [Color(0xFF00008B), Colors.white, Color(0xFFFF0000)], accent: Color(0xFF00008B)),
  'IN': (colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)], accent: Color(0xFFFF9933)),
  'BR': (colors: [Color(0xFF009739), Color(0xFFFEDD00), Color(0xFF012169)], accent: Color(0xFF009739)),
  'KR': (colors: [Colors.white, Color(0xFFCD2E3A), Color(0xFF0047A0)], accent: Color(0xFFCD2E3A)),
  'HK': (colors: [Color(0xFFDE2910), Colors.white], accent: Color(0xFFDE2910)),
  'AE': (colors: [Color(0xFFFF0000), Color(0xFF00732F), Colors.white], accent: Color(0xFF00732F)),
  'UA': (colors: [Color(0xFF0057B7), Color(0xFFFFDD00)], accent: Color(0xFF0057B7)),
  'PT': (colors: [Color(0xFF046A38), Color(0xFFDA291C)], accent: Color(0xFFDA291C)),
  'AT': (colors: [Color(0xFFED2939), Colors.white], accent: Color(0xFFED2939)),
  'BE': (colors: [Color(0xFF000000), Color(0xFFFAE042), Color(0xFFED2939)], accent: Color(0xFFFAE042)),
  'DK': (colors: [Color(0xFFC60C30), Colors.white], accent: Color(0xFFC60C30)),
  'IE': (colors: [Color(0xFF169B62), Colors.white, Color(0xFFFF883E)], accent: Color(0xFF169B62)),
  'GR': (colors: [Color(0xFF0D5EAF), Colors.white], accent: Color(0xFF0D5EAF)),
  'RO': (colors: [Color(0xFF002B7F), Color(0xFFFCD116), Color(0xFFCE1126)], accent: Color(0xFFFCD116)),
  'CZ': (colors: [Colors.white, Color(0xFFD7141A), Color(0xFF11457E)], accent: Color(0xFF11457E)),
  'HU': (colors: [Color(0xFFCE2939), Colors.white, Color(0xFF477050)], accent: Color(0xFFCE2939)),
  'IL': (colors: [Color(0xFF0038B8), Colors.white], accent: Color(0xFF0038B8)),
  'MX': (colors: [Color(0xFF006847), Colors.white, Color(0xFFCE1126)], accent: Color(0xFF006847)),
  'ID': (colors: [Color(0xFFFF0000), Colors.white], accent: Color(0xFFFF0000)),
  'TH': (colors: [Color(0xFFA51931), Colors.white, Color(0xFF2D2A4A)], accent: Color(0xFF2D2A4A)),
  'VN': (colors: [Color(0xFFDA251D), Color(0xFFFFCD00)], accent: Color(0xFFDA251D)),
  'MY': (colors: [Color(0xFF010066), Color(0xFFCC0000), Color(0xFFFFCC00)], accent: Color(0xFFCC0000)),
  'PH': (colors: [Color(0xFF0038A8), Color(0xFFCE1126), Colors.white], accent: Color(0xFF0038A8)),
  'NZ': (colors: [Color(0xFF00247D), Colors.white, Color(0xFFCC142B)], accent: Color(0xFF00247D)),
  'IS': (colors: [Color(0xFF02529C), Colors.white, Color(0xFFDC1E35)], accent: Color(0xFF02529C)),
  'EE': (colors: [Color(0xFF0072CE), Color(0xFF000000), Colors.white], accent: Color(0xFF0072CE)),
  'LV': (colors: [Color(0xFF9E3039), Colors.white], accent: Color(0xFF9E3039)),
  'LT': (colors: [Color(0xFFFDB913), Color(0xFF006A44), Color(0xFFC1272D)], accent: Color(0xFFFDB913)),
  'ZA': (colors: [Color(0xFF007A4D), Color(0xFFDE3831), Color(0xFF002395)], accent: Color(0xFF007A4D)),
};

/// Representative colors per location, used for the flag icon's own
/// rendering and for multi-stop glows (e.g. the connect button). Falls
/// back to a generated single-hue set for Auto / uncurated codes.
List<Color> flagColorsFor(String countryCode) {
  final curated = _curatedFlags[countryCode.toUpperCase()];
  if (curated != null) return curated.colors;
  final base = _generatedAccentFor(countryCode);
  return [base, Color.lerp(base, Colors.white, 0.55) ?? base, base];
}

/// A single representative color per location, used to tint the background
/// glow, the side rail, and card borders. Deliberately ONE color rather
/// than the flag's full palette — washing a large flat surface (the whole
/// app background, a card border) in 2-3 raw flag colors at once reads as
/// muddy, not "on brand", so one vivid, well-chosen color is used there
/// instead. Multi-color surfaces (the flag icon itself, the connect
/// button's glow/shimmer) use [flagColorsFor]'s full list, not this.
Color accentColorFor(String countryCode) {
  final curated = _curatedFlags[countryCode.toUpperCase()];
  if (curated != null) return curated.accent;
  return _generatedAccentFor(countryCode);
}

/// Deterministically turns a country code into a color by hashing it to a
/// hue — same code always gives the same color, different codes are spread
/// around the hue wheel, and saturation/lightness are fixed to values that
/// read well as a glow against the app's dark background. This is what
/// makes "does the color adapt automatically for a location we haven't
/// curated?" true by construction rather than something to remember — it
/// just won't be the location's *real* flag colors until someone adds a
/// [_curatedFlags] entry for it.
Color _generatedAccentFor(String countryCode) {
  if (countryCode.isEmpty) return WbColors.waveCyan;
  final hash = countryCode.toUpperCase().codeUnits.fold<int>(
        0,
        (acc, unit) => (acc * 31 + unit) & 0x7fffffff,
      );
  final hue = (hash % 360).toDouble();
  return HSLColor.fromAHSL(1.0, hue, 0.62, 0.56).toColor();
}

/// Two real, vivid colors from a location's actual flag — for surfaces that
/// *can* carry two colors well, like the connect button's glow/shimmer,
/// where [accentColorFor]'s single flat tint would under-use the flag.
/// Picks [accentColorFor] as the first color, then the first other palette
/// color that isn't too close to white or black (a white or black glow
/// reads as "no glow" rather than as a color) — falling back to a lighter
/// tint of the accent when the flag genuinely only has white/black besides
/// its main color (e.g. Japan).
List<Color> accentPairFor(String countryCode) {
  final primary = accentColorFor(countryCode);
  final palette = flagColorsFor(countryCode);
  Color? secondary;
  for (final c in palette) {
    if (c.toARGB32() == primary.toARGB32()) continue;
    final luminance = c.computeLuminance();
    if (luminance > 0.85 || luminance < 0.08) continue;
    secondary = c;
    break;
  }
  secondary ??= Color.lerp(primary, Colors.white, 0.4) ?? primary;
  return [primary, secondary];
}

String flagEmoji(String countryCode) {
  if (countryCode.length != 2) return '';
  final upper = countryCode.toUpperCase();
  return String.fromCharCodes(upper.codeUnits.map((c) => 0x1F1E6 - 65 + c));
}
