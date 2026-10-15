import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/features/home/location_bar.dart';
import 'package:wavebreak/services/core_api/models.dart';
import 'package:wavebreak/services/custom_servers/node_label.dart';
import 'package:wavebreak/services/custom_servers/share_link_parsing.dart';
import 'package:wavebreak/services/vpn/server_catalog.dart';

void main() {
  void expectLabel(String label, String? code, String country, String place) {
    final l = parseNodeLabel(label);
    expect([l.countryCode, l.country, l.place], [code, country, place],
        reason: label);
  }

  test('WAVEBREAK names read as before', () {
    expectLabel('🇳🇱 Netherlands, Amsterdam (CDN)', 'NL', 'Netherlands',
        'Amsterdam (CDN)');
    expectLabel(
        '🇷🇺 Russia (Direct-TLS)', 'RU', 'Russia', 'Russia (Direct-TLS)');
    expectLabel('🇩🇪 Germany (VLESS)', 'DE', 'Germany', 'Germany (VLESS)');
    expectLabel('🇹🇷 Turkey, Istanbul (Hysteria2)', 'TR', 'Turkey',
        'Istanbul (Hysteria2)');
  });

  test('third-party provider names', () {
    expectLabel(
        '🇩🇪 Германия | VLESS | Reality', 'DE', 'Германия', 'Германия');
    expectLabel('🇩🇪 Германия | VLESS | 2', 'DE', 'Германия', 'Германия 2');
    expectLabel('[NL] Amsterdam 🚀', 'NL', 'Netherlands', 'Amsterdam');
    expectLabel('DE-Frankfurt • Reality', 'DE', 'Germany', 'Frankfurt');
    expectLabel('NL-1', 'NL', 'Netherlands', 'Netherlands 1');
    expectLabel('Turkey Istanbul #3', 'TR', 'Turkey', 'Istanbul 3');
    expectLabel('🇫🇮 Финляндия, Хельсинки ⚡️', 'FI', 'Финляндия', 'Хельсинки');
    expectLabel('🇺🇸 USA - New York - VMess WS', 'US', 'USA', 'New York');
    expectLabel('Турция Стамбул', 'TR', 'Турция', 'Стамбул');
    expectLabel('🇬🇧 London', 'GB', 'United Kingdom', 'London');
  });

  test('a name with no country stays as it is', () {
    expectLabel('My server', null, 'My server', 'My server');
    expectLabel('⚡ Fast node', null, 'Fast node', 'Fast node');
  });

  LocationItem fromLink(String link) => locationFromUri(Uri.parse(link), link);

  test('the protocol comes from the link for third-party nodes', () {
    expect(
        protocolLabel(fromLink(
            'vless://id@cdn.example.com:443?security=tls#%F0%9F%87%A9%F0%9F%87%AA%20DE')),
        'VLESS');
    expect(protocolLabel(fromLink('vless://id@h:443?security=reality#x')),
        'REALITY');
    expect(protocolLabel(fromLink('vmess://eyJ2IjoiMiJ9')), 'VMess');
    expect(
        protocolLabel(fromLink('trojan://pw@h:443#Trojan%20node')), 'Trojan');
    expect(protocolLabel(fromLink('ss://YWVzOnB3@h:8388#ss')), 'Shadowsocks');
    expect(protocolLabel(fromLink('hy2://pw@h:443#x')), 'Hysteria2');
    // WAVEBREAK's own names still decide for its links.
    expect(
        protocolLabel(fromLink(
            'vless://id@h:443?security=tls#%F0%9F%87%B9%F0%9F%87%B7%20Turkey%2C%20Istanbul%20(Direct-TLS)')),
        'Direct');
  });

  test('two nodes of one city in a third-party list are two rows', () {
    final a =
        fromLink('vless://a@1.1.1.1:443#%F0%9F%87%A9%F0%9F%87%AA%20Frankfurt');
    final b =
        fromLink('vless://b@2.2.2.2:443#%F0%9F%87%A9%F0%9F%87%AA%20Frankfurt');
    final places = buildPlaces('group-1', [a, b]);
    expect(places, hasLength(2));
    expect(places.map((p) => p.key).toSet(), hasLength(2));
    // WAVEBREAK's own section still folds them.
    expect(buildPlaces('wavebreak', [a, b]), hasLength(1));
  });
}
