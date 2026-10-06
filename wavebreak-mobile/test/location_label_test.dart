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
