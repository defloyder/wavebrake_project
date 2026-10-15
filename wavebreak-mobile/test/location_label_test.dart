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

  test('flag tint mixes the flag and never lands on the amber state color', () {
    for (final code in ['DE', 'ES', 'BE', 'RO', 'LT', 'RU', 'TR', 'NL']) {
      final hue = HSLColor.fromColor(accentColorFor(code)).hue;
      expect(hue < 36 || hue > 62, isTrue, reason: '$code hue $hue');
    }
    // Germany: black + red + gold → orange, not the gold alone.
    final de = HSLColor.fromColor(accentColorFor('DE')).hue;
    expect(de, inInclusiveRange(15, 35));
  });
}
