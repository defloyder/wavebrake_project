import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/core/theme/flag_colors.dart';
import 'package:wavebreak/features/home/location_bar.dart';
import 'package:wavebreak/services/custom_servers/share_link_parsing.dart';

void main() {
  test('Core link "🇩🇪 Germany (VLESS)" reads as Germany, REALITY', () {
    const raw = 'vless://id@de.example:443?type=tcp&security=reality'
        '#%F0%9F%87%A9%F0%9F%87%AA%20Germany%20(VLESS)';
    final l = locationFromUri(Uri.parse(raw), raw);
    expect(l.countryCode, 'DE');
    expect(l.country, 'Germany');
    expect(splitPlaceAndProtocol(l.city).$1, 'Germany');
    expect(protocolLabel(l), 'REALITY');
  });

  test(
      'a WAVEBREAK (own-domain) custom note shows verbatim, '
      'not a generic scheme name', () {
    const raw = 'vless://id@dl.wavebreak.com.tr:9443?type=ws&security=tls'
        '#%F0%9F%87%B7%F0%9F%87%BA%20Russia%2C%20Moscow'
        '%20%28YouTube%20%D0%B1%D0%B5%D0%B7%20%D1%80%D0%B5%D0%BA%D0%BB%D0%B0%D0%BC%D1%8B%29';
    final l = locationFromUri(Uri.parse(raw), raw);
    expect(l.country, 'Russia');
    expect(splitPlaceAndProtocol(l.city).$1, 'Moscow');
    expect(protocolLabel(l), 'YouTube без рекламы');
  });

  test(
      'the same unrecognized note on a third-party (non-WAVEBREAK) domain '
      'still falls back to the generic scheme name (owner, 12.10 regression)',
      () {
    const raw = 'vless://id@some-other-host.example:443?type=ws&security=tls'
        '#Germany%20(Totally%20Custom%20Note)';
    final l = locationFromUri(Uri.parse(raw), raw);
    expect(protocolLabel(l), 'VLESS');
  });

  test('flag tint never lands on the amber state color', () {
    for (final code in [
      'DE',
      'ES',
      'BE',
      'RO',
      'LT',
      'RU',
      'TR',
      'NL',
      'SE',
      'UA'
    ]) {
      for (final c in [accentColorFor(code), secondAccentFor(code)]) {
        if (c == null) continue;
        final hue = HSLColor.fromColor(c).hue;
        expect(hue < 36 || hue > 62, isTrue, reason: '$code hue $hue');
      }
    }
  });

  double hue(Color c) => HSLColor.fromColor(c).hue;
  bool near(double h, double target) {
    final d = (h - target).abs();
    return (d < 360 - d ? d : 360 - d) < 20;
  }

  test('the flag\'s own two main colours, from the measured palette (16.10)',
      () {
    // Bulgaria (green, white, red): green and red — it used to be pink.
    expect(near(hue(accentColorFor('BG')), 160), isTrue);
    expect(near(hue(secondAccentFor('BG')!), 6), isTrue);
    // Germany: gold first (shown as orange, never the amber state), red
    // second — red first left the app looking untinted (16.10).
    expect(near(hue(accentColorFor('DE')), 26), isTrue);
    expect(near(hue(secondAccentFor('DE')!), 0), isTrue);
    // Russia: blue and red; Turkey and Switzerland: red only.
    expect(near(hue(accentColorFor('RU')), 220), isTrue);
    expect(near(hue(secondAccentFor('RU')!), 4), isTrue);
    expect(secondAccentFor('TR'), isNull);
    expect(secondAccentFor('CH'), isNull);
  });

  test('every country has a measured palette', () {
    expect(flagColorsFor('BG'), hasLength(3));
    expect(flagColorsFor('FR').first, const Color(0xFF002654));
    for (final code in ['AE', 'GB', 'SE', 'CH', 'IT', 'KZ', 'BR', 'JP']) {
      expect(flagChromatics(code), isNotEmpty, reason: code);
    }
  });

  test('the UI palette: every flag colour, emblems too, edge blends out', () {
    String hex(Color c) => c.toARGB32().toRadixString(16).substring(2);
    // Germany: red, black (as graphite) and gold — all three.
    expect(flagUiPalette('DE').map(hex), ['ec1313', '4a505e', 'ecc213']);
    // Emblems count: Turkey's white crescent, China's yellow stars.
    expect(flagUiPalette('TR'), hasLength(2));
    expect(flagUiPalette('CN'), hasLength(2));
    // Kazakhstan: blue and yellow, not the green edge blends between them.
    expect(flagUiPalette('KZ'), hasLength(2));
    // A colour for controls: the first that isn't white or graphite.
    expect(firstChromatic(flagUiPalette('JP')), isNotNull);
    expect(hex(firstChromatic(flagUiPalette('JP'))!), 'ec1347');
  });
}
