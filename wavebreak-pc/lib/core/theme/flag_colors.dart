import 'package:flutter/material.dart';

import 'wb_colors.dart';

/// Real, curated flag colors for locations we can realistically expect to
/// see (current + likely future server countries). Each entry is the
/// flag's actual palette (2-4 colors, in roughly the order they appear on
/// the flag). The UI tint is their mix — see [accentColorFor].
///
/// Anything NOT in this table (some exotic location a subscription adds
/// that we haven't curated yet) falls through to [_generatedPaletteFor],
/// which derives a *consistent, distinct* — but not necessarily
/// flag-accurate — color from the country code itself. So: yes, new
/// countries automatically get a color, but only entries in this table are
/// guaranteed to be the location's real flag colors. Adding a new country
/// here later is a one-line change.
const _curatedFlags = <String, List<Color>>{
  'TR': [Color(0xFFE30A17), Colors.white, Color(0xFFE30A17)],
  'NL': [Color(0xFFAE1C28), Colors.white, Color(0xFF21468B)],
  'RU': [Colors.white, Color(0xFF0039A6), Color(0xFFD52B1E)],
  'FI': [Color(0xFF002F6C), Colors.white, Color(0xFF002F6C)],
  'US': [Color(0xFFB22234), Colors.white, Color(0xFF3C3B6E)],
  'GB': [Color(0xFF012169), Colors.white, Color(0xFFC8102E)],
  'DE': [Color(0xFF000000), Color(0xFFDD0000), Color(0xFFFFCE00)],
  'FR': [Color(0xFF0055A4), Colors.white, Color(0xFFEF4135)],
  'IT': [Color(0xFF009246), Colors.white, Color(0xFFCE2B37)],
  'ES': [Color(0xFFAA151B), Color(0xFFF1BF00), Color(0xFFAA151B)],
  'PL': [Colors.white, Color(0xFFDC143C)],
  'SE': [Color(0xFF006AA7), Color(0xFFFECC02)],
  'NO': [Color(0xFFEF2B2D), Colors.white, Color(0xFF002868)],
  'CH': [Color(0xFFFF0000), Colors.white],
  'CA': [Color(0xFFFF0000), Colors.white],
  'JP': [Colors.white, Color(0xFFBC002D)],
  'SG': [Color(0xFFEF3340), Colors.white],
  'AU': [Color(0xFF00008B), Colors.white, Color(0xFFFF0000)],
  'IN': [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
  'BR': [Color(0xFF009739), Color(0xFFFEDD00), Color(0xFF012169)],
  'KR': [Colors.white, Color(0xFFCD2E3A), Color(0xFF0047A0)],
  'HK': [Color(0xFFDE2910), Colors.white],
  'AE': [Color(0xFFFF0000), Color(0xFF00732F), Colors.white],
  'UA': [Color(0xFF0057B7), Color(0xFFFFDD00)],
  'PT': [Color(0xFF046A38), Color(0xFFDA291C)],
  'AT': [Color(0xFFED2939), Colors.white],
  'BE': [Color(0xFF000000), Color(0xFFFAE042), Color(0xFFED2939)],
  'DK': [Color(0xFFC60C30), Colors.white],
  'IE': [Color(0xFF169B62), Colors.white, Color(0xFFFF883E)],
  'GR': [Color(0xFF0D5EAF), Colors.white],
  'RO': [Color(0xFF002B7F), Color(0xFFFCD116), Color(0xFFCE1126)],
  'CZ': [Colors.white, Color(0xFFD7141A), Color(0xFF11457E)],
  'HU': [Color(0xFFCE2939), Colors.white, Color(0xFF477050)],
  'IL': [Color(0xFF0038B8), Colors.white],
  'MX': [Color(0xFF006847), Colors.white, Color(0xFFCE1126)],
  'ID': [Color(0xFFFF0000), Colors.white],
  'TH': [Color(0xFFA51931), Colors.white, Color(0xFF2D2A4A)],
  'VN': [Color(0xFFDA251D), Color(0xFFFFCD00)],
  'MY': [Color(0xFF010066), Color(0xFFCC0000), Color(0xFFFFCC00)],
  'PH': [Color(0xFF0038A8), Color(0xFFCE1126), Colors.white],
  'NZ': [Color(0xFF00247D), Colors.white, Color(0xFFCC142B)],
  'IS': [Color(0xFF02529C), Colors.white, Color(0xFFDC1E35)],
  'EE': [Color(0xFF0072CE), Color(0xFF000000), Colors.white],
  'LV': [Color(0xFF9E3039), Colors.white],
  'LT': [Color(0xFFFDB913), Color(0xFF006A44), Color(0xFFC1272D)],
  'ZA': [Color(0xFF007A4D), Color(0xFFDE3831), Color(0xFF002395)],
};

/// Representative colors per location, used for the flag icon's own
/// rendering and for multi-stop glows (e.g. the connect button). Falls
/// back to a generated single-hue set for Auto / uncurated codes.
List<Color> flagColorsFor(String countryCode) {
  final curated = _curatedFlags[countryCode.toUpperCase()];
  if (curated != null) return curated;
  final base = _generatedAccentFor(countryCode);
  return [base, Color.lerp(base, Colors.white, 0.55) ?? base, base];
}

/// A single representative color per location, used to tint the background
/// waves, the sphere and the glass cards: all of the flag's colors mixed
/// together, then brought to a glow-friendly saturation and lightness.
///
/// Owner (06.10): it used to be one hand-picked flag color — gold for
/// Germany, which read as the app's amber "no traffic" state. Mixing the
/// whole flag (black + red + gold → a warm orange) keeps it the place's
/// own color. A mix that still lands in the amber band is pushed to
/// orange so it never looks like that state. Multi-color surfaces (the
/// flag icon, the connect button's glow) use [flagColorsFor] instead.
Color accentColorFor(String countryCode) {
  final curated = _curatedFlags[countryCode.toUpperCase()];
  if (curated == null) return _generatedAccentFor(countryCode);
  return mixFlagColors(curated);
}

/// The mix behind [accentColorFor]; visible for tests.
Color mixFlagColors(List<Color> colors) {
  var r = 0.0, g = 0.0, b = 0.0;
  for (final c in colors) {
    r += c.r;
    g += c.g;
    b += c.b;
  }
  final n = colors.length;
  final mixed = HSLColor.fromColor(Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n));
  // Grey mix (e.g. only black and white): nothing to tint with.
  if (mixed.saturation < 0.05) return WbColors.waveCyan;
  var hue = mixed.hue;
  if (hue >= 36 && hue <= 62) hue = 26;
  return HSLColor.fromAHSL(
    1,
    hue,
    mixed.saturation.clamp(0.65, 0.85),
    mixed.lightness.clamp(0.5, 0.6),
  ).toColor();
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
