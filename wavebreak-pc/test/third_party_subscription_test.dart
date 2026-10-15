import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/core/i18n/app_strings.dart';
import 'package:wavebreak/features/shared/subscription_section.dart';
import 'package:wavebreak/services/custom_servers/custom_server_controller.dart';

// P17: a third-party subscription in any format becomes its own section
// with the provider's title, traffic, end date and update interval; nodes
// this phone can't run stay listed but greyed out. Keys are made up.
const _clash = '''
proxies:
  - name: "🇩🇪 Germany, Frankfurt"
    type: vless
    server: de.example.com
    port: 443
    uuid: 00000000-0000-4000-8000-000000000001
    tls: true
    servername: www.example.org
    reality-opts: {public-key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA, short-id: ab12}
  - {name: TUIC node, type: tuic, server: t.example.com, port: 443, uuid: 00000000-0000-4000-8000-000000000002, password: x}
  - {name: Old SSR, type: ssr, server: s.example.com, port: 443}
''';

void main() {
  final now = DateTime.utc(2026, 10, 6, 12);

  test('Clash profile with provider headers becomes one section', () {
    final group = CustomServerController.groupFromResponse(
      _clash,
      {
        'subscription-userinfo': [
          'upload=1073741824; download=2147483648; total=107374182400; expire=1798675200'
        ],
        'profile-title': ['base64:0JzQvtC5IFZQTg=='],
        'profile-update-interval': ['6'],
      },
      id: 'g1',
      link: 'https://panel.example.com/sub/abc',
      now: now,
    )!;

    expect(group.name, 'Мой VPN');
    expect(group.usedBytes, 3 * 1073741824);
    expect(group.totalBytes, 107374182400);
    expect(group.expiresAt, DateTime.utc(2026, 12, 31));
    expect(group.updateIntervalHours, 6);
    expect(group.servers, hasLength(3));

    final de = group.servers.first;
    expect(de.countryCode, 'DE');
    expect(de.available, isTrue);
    expect(de.rawLink, startsWith('vless://'));
    // Windows runs sing-box: TUIC works there, only SSR stays unsupported
    // (on Android's Xray both do).
    expect(group.servers.where((s) => !s.available).map((s) => s.country),
        ['Old SSR']);

    expect(group.isStale(now.add(const Duration(hours: 5))), isFalse);
    expect(group.isStale(now.add(const Duration(hours: 6))), isTrue);

    final section = buildSubscriptionSections(
      wavebreakLocations: const [],
      customGroups: [group],
      s: kRussianStrings,
    ).last;
    expect(section.title, 'Мой VPN');
    expect(section.limitsTraffic, '3 ГБ / 100 ГБ · до 31.12.2026');
  });

  test('plain base64 body without headers still works, no limits line', () {
    const body =
        'dmxlc3M6Ly8wMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMjFAYS5leGFtcGxlLmNvbTo0NDM/c2VjdXJpdHk9dGxzI0E=';
    final group = CustomServerController.groupFromResponse(body, const {},
        id: 'g2', link: 'https://b.example.com/s', now: now)!;
    expect(group.name, 'b.example.com');
    expect(group.servers.single.available, isTrue);
    final section = buildSubscriptionSections(
      wavebreakLocations: const [],
      customGroups: [group],
      s: kEnglishStrings,
    ).last;
    expect(section.limitsTraffic, isNull);
  });

  test('a body with no nodes is rejected', () {
    expect(
      CustomServerController.groupFromResponse('<html>404</html>', const {},
          id: 'g3', link: 'https://c.example.com/s'),
      isNull,
    );
  });
}
