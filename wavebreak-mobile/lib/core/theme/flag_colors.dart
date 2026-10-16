import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'flag_palettes.dart';
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
/// rendering and for multi-stop glows (e.g. the connect button): the
/// flag's real colours, largest share first (flag_palettes.dart,
/// measured from the flag library for every country). Falls back to the
/// hand-picked set, then a generated single-hue set (Auto, unknown codes).
List<Color> flagColorsFor(String countryCode) {
  final code = countryCode.toUpperCase();
  final measured = flagPalettes[code];
  if (measured != null && measured.isNotEmpty) {
    return [for (final (c, _) in measured) Color(c)];
  }
  final curated = _curatedFlags[code];
  if (curated != null) return curated;
  final base = _generatedAccentFor(countryCode);
  return [base, Color.lerp(base, Colors.white, 0.55) ?? base, base];
}

bool _chromatic(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.saturation > 0.25 && hsl.lightness > 0.1 && hsl.lightness < 0.92;
}

/// The flag's colours that can tint (white, black and greys left out),
/// largest share first.
List<Color> flagChromatics(String countryCode) => [
      for (final c in flagColorsFor(countryCode))
        if (_chromatic(c)) c,
    ];

/// A flag colour as an accent: glow-friendly saturation and lightness; a
/// yellow is pushed to orange so it never reads as the amber "no traffic"
/// state (owner, 06.10).
Color _asAccent(Color c) {
  final hsl = HSLColor.fromColor(c);
  var hue = hsl.hue;
  if (hue >= 36 && hue <= 62) hue = 26;
  return HSLColor.fromAHSL(1, hue, hsl.saturation.clamp(0.65, 0.85),
          hsl.lightness.clamp(0.5, 0.6))
      .toColor();
}

/// Hue distance in degrees (0..180).
double _hueGap(double a, double b) {
  final d = (a - b).abs();
  return math.min(d, 360 - d);
}

/// The app's own crimson: a flag colour this close in hue doesn't show the
/// flag at all — Germany's red made the whole app look untinted (16.10).
final double _appRedHue = HSLColor.fromColor(WbColors.crimson).hue;

/// The flag's colours as accents, the one that shows the flag first: the
/// largest colour unlike the app's own red, then the rest by share.
List<Color> _flagAccents(String countryCode) {
  final accents = [for (final c in flagChromatics(countryCode)) _asAccent(c)];
  final i = accents
      .indexWhere((c) => _hueGap(HSLColor.fromColor(c).hue, _appRedHue) > 20);
  if (i > 0) accents.insert(0, accents.removeAt(i));
  return accents;
}

/// The location's main colour (owner, 16.10: every flag its own look). The
/// flag's largest colour that isn't the app's red — Germany gold (shown as
/// orange, never the amber state), Russia blue, Bulgaria green; an all-red
/// flag (Turkey, Switzerland) stays red. White, black and grey never tint;
/// a flag of only those keeps the app's cyan.
Color accentColorFor(String countryCode) {
  if (countryCode.isEmpty) return WbColors.waveCyan;
  final accents = _flagAccents(countryCode);
  if (accents.isEmpty) {
    return flagPalettes.containsKey(countryCode.toUpperCase())
        ? WbColors.waveCyan
        : _generatedAccentFor(countryCode);
  }
  return accents.first;
}

/// The flag's second colour, distinct in hue from the first, or null for a
/// one-colour flag — shown beside [accentColorFor] in equal measure (the
/// background waves alternate the two).
Color? secondAccentFor(String countryCode) {
  final accents = _flagAccents(countryCode);
  if (accents.length < 2) return null;
  final first = HSLColor.fromColor(accents.first).hue;
  for (final c in accents.skip(1)) {
    if (_hueGap(HSLColor.fromColor(c).hue, first) >= 25) return c;
  }
  return null;
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
  final mixed = HSLColor.fromColor(
      Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n));
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
  final secondary = secondAccentFor(countryCode) ??
      Color.lerp(primary, Colors.white, 0.4) ??
      primary;
  return [primary, secondary];
}

String flagEmoji(String countryCode) {
  if (countryCode.length != 2) return '';
  final upper = countryCode.toUpperCase();
  return String.fromCharCodes(upper.codeUnits.map((c) => 0x1F1E6 - 65 + c));
}

/// The flag's colours for the UI — all of them, emblems included (Turkey's
/// white crescent, Japan's red disc), each its own colour, not mixed
/// (owner, 16.10: "all three colours used, not mixed, but in harmony").
/// Brought to one saturation and lightness band so they sit together; white
/// becomes a soft white and black a graphite that shows on the dark
/// background. Edge blends of two colours (anti-aliasing, a few % of the
/// flag) are left out. Largest share first.
List<Color> flagUiPalette(String countryCode) {
  final measured = flagPalettes[countryCode.toUpperCase()];
  if (measured == null || measured.isEmpty) {
    return countryCode.isEmpty ? const [] : [accentColorFor(countryCode)];
  }
  final kept = <Color>[];
  for (final (value, share) in measured) {
    final c = Color(value);
    if (share < 0.08 && _isBlendOf(c, kept)) continue;
    kept.add(c);
  }
  final ui = <Color>[];
  for (final c in kept) {
    final h = _harmonize(c);
    if (!ui.any((u) => _sameUiColor(u, h))) ui.add(h);
  }
  return ui;
}

/// The first colour of [flagUiPalette] that can colour a control (a switch,
/// a button): not white or graphite.
Color? firstChromatic(List<Color> palette) {
  for (final c in palette) {
    if (HSLColor.fromColor(c).saturation >= 0.3) return c;
  }
  return null;
}

const _softWhite = Color(0xFFE6EAF0);
const _graphite = Color(0xFF4A505E);
const _neutralGrey = Color(0xFF8A909C);

Color _harmonize(Color c) {
  final hsl = HSLColor.fromColor(c);
  if (hsl.lightness > 0.9 || (hsl.lightness > 0.85 && hsl.saturation < 0.35)) {
    return _softWhite;
  }
  if (hsl.lightness < 0.15) return _graphite;
  if (hsl.saturation < 0.15) return _neutralGrey;
  return HSLColor.fromAHSL(1, hsl.hue, hsl.saturation.clamp(0.6, 0.85),
          hsl.lightness.clamp(0.5, 0.62))
      .toColor();
}

bool _sameUiColor(Color a, Color b) {
  if (a == b) return true;
  final ha = HSLColor.fromColor(a), hb = HSLColor.fromColor(b);
  if (ha.saturation < 0.3 || hb.saturation < 0.3) return false;
  return _hueGap(ha.hue, hb.hue) < 18;
}

/// [c] lies on the line between two colours already kept: an edge blend.
bool _isBlendOf(Color c, List<Color> kept) {
  final p = [c.r * 255, c.g * 255, c.b * 255];
  for (var i = 0; i < kept.length; i++) {
    for (var j = i + 1; j < kept.length; j++) {
      final a = [kept[i].r * 255, kept[i].g * 255, kept[i].b * 255];
      final b = [kept[j].r * 255, kept[j].g * 255, kept[j].b * 255];
      final ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
      final ap = [p[0] - a[0], p[1] - a[1], p[2] - a[2]];
      final len2 = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2];
      if (len2 == 0) continue;
      final t = ((ap[0] * ab[0] + ap[1] * ab[1] + ap[2] * ab[2]) / len2)
          .clamp(0.0, 1.0);
      final dx = p[0] - (a[0] + ab[0] * t),
          dy = p[1] - (a[1] + ab[1] * t),
          dz = p[2] - (a[2] + ab[2] * t);
      if (math.sqrt(dx * dx + dy * dy + dz * dz) < 32) return true;
    }
  }
  return false;
}
