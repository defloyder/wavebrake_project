import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/core_api/models.dart';
import 'package:wavebreak/services/vpn/protocol_fallback.dart';

LocationItem _loc(String id, String code, String city,
        {bool available = true}) =>
    LocationItem(
      id: id,
      countryCode: code,
      country: code,
      city: city,
      available: available,
    );

void main() {
  // Best ping first, as auto select ranks them.
  final trDirect = _loc('tr-d', 'TR', 'Istanbul (Direct-TLS)');
  final de = _loc('de', 'DE', 'Frankfurt');
  final trHy = _loc('tr-h', 'TR', 'Istanbul (Hysteria2)');
  final lte = _loc('lte', 'RU', 'LTE (БС)');
  final ranked = [trDirect, de, trHy, lte];

  test('the same place\'s other protocol first, then the next by ping', () {
    expect(nextAutoCandidate(ranked, trDirect, {}), trHy);
    expect(nextAutoCandidate(ranked, trHy, {'tr-d'}), de);
    expect(nextAutoCandidate(ranked, de, {'tr-d', 'tr-h'}), lte);
  });

  test('a name note that is not a protocol is its own place', () {
    final lte2 = _loc('lte2', 'RU', 'LTE');
    expect(nextAutoCandidate([lte, de, lte2], lte, {}), de);
  });

  test('skips unavailable and tried ones; null when nothing is left', () {
    final off = _loc('off', 'TR', 'Istanbul (CDN)', available: false);
    expect(nextAutoCandidate([trDirect, off, de], trDirect, {}), de);
    expect(nextAutoCandidate(ranked, lte, {'tr-d', 'tr-h', 'de'}), isNull);
  });
}
