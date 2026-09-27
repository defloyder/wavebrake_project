import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/core/i18n/app_strings.dart';
import 'package:wavebreak/core/storage/secure_store.dart';
import 'package:wavebreak/features/shared/subscription_texts.dart';
import 'package:wavebreak/features/shared/traffic_format.dart';
import 'package:wavebreak/services/core_api/core_gateway.dart';
import 'package:wavebreak/services/core_api/models.dart';
import 'package:wavebreak/services/vpn/personal_locations.dart';

import 'test_helpers.dart';

const _credential = '11111111-2222-4333-8444-555555555555';

const _links = [
  'vless://$_credential@45.15.41.3:443?encryption=none&flow=xtls-rprx-vision&fp=chrome'
      '&pbk=test-key&security=reality&sid=ab12&sni=r.example.test&type=tcp'
      '#%F0%9F%87%B9%F0%9F%87%B7%20Turkey%2C%20Istanbul%20%28VLESS%29',
  'vless://$_credential@direct.example.test:443?encryption=none&host=direct.example.test'
      '&path=%2Fwvb-dt&security=tls&sni=direct.example.test&type=ws'
      '#%F0%9F%87%B9%F0%9F%87%B7%20Turkey%2C%20Istanbul%20%28Direct-TLS%29',
  'hysteria2://$_credential@45.15.41.3:443/?alpn=h3&sni=hy2.example.test'
      '#%F0%9F%87%B9%F0%9F%87%B7%20Turkey%2C%20Istanbul%20%28Hysteria2%29',
];

/// Only personalAccess() matters here; anything else is a test bug.
class _FakeGateway implements CoreGateway {
  _FakeGateway(this.answer);

  Future<PersonalAccess?> Function() answer;

  @override
  Future<PersonalAccess?> personalAccess() => answer();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(setUpTestEnvironment);

  group('personal access (bug 10)', () {
    test('uses the account credential from Core and saves it', () async {
      final gateway = _FakeGateway(() async => const PersonalAccess(credentialId: _credential, links: _links));

      final locations = await PersonalLocations.load(gateway);

      expect(locations, hasLength(3));
      expect(locations.every((l) => l.rawLink!.contains(_credential)), isTrue);
      final saved = jsonDecode((await SecureStore.read(SecureStore.personalAccess))!) as Map<String, dynamic>;
      expect(saved['credential_id'], _credential);
    });

    test('falls back to the saved access when Core is unreachable', () async {
      await PersonalLocations.load(_FakeGateway(() async => const PersonalAccess(credentialId: _credential, links: _links)));

      final offline = await PersonalLocations.load(_FakeGateway(() async => throw Exception('no network')));

      expect(offline, hasLength(3));
    });

    test('no active subscription drops the saved access', () async {
      await PersonalLocations.load(_FakeGateway(() async => const PersonalAccess(credentialId: _credential, links: _links)));

      final none = await PersonalLocations.load(_FakeGateway(() async => null));

      expect(none, isEmpty);
      expect(await SecureStore.read(SecureStore.personalAccess), isNull);
      // ...and it is not resurrected offline afterwards: nothing to connect
      // with is an error the screen can offer a retry for, not "no servers".
      expect(PersonalLocations.load(_FakeGateway(() async => throw Exception('offline'))), throwsException);
    });

    test('Core unreachable with nothing saved is an error, not an empty list', () async {
      expect(PersonalLocations.load(_FakeGateway(() async => throw Exception('no network'))), throwsException);
    });

    test('sign-out forgets the credential', () async {
      await PersonalLocations.load(_FakeGateway(() async => const PersonalAccess(credentialId: _credential, links: _links)));
      await SecureStore.clearSession();
      expect(await SecureStore.read(SecureStore.personalAccess), isNull);
    });
  });

  group('subscription model', () {
    test('reads Core field names, admin overrides and the grace period', () {
      final sub = SubscriptionInfo.fromJson({
        'id': 's1',
        'status': 'past_due',
        'plan_id': 'p1',
        'current_period_end': '2026-10-01T10:00:00Z',
        'traffic_limit_bytes_snapshot': 107374182400,
        'traffic_limit_override_bytes': 214748364800,
        'device_limit_snapshot': 3,
        'device_limit_override': 5,
        'grace_ends_at': '2026-10-08T10:00:00Z',
      });

      expect(sub.expiresAt, DateTime.utc(2026, 10, 1, 10));
      expect(sub.trafficLimitBytes, 214748364800);
      expect(sub.deviceLimit, 5);
      expect(sub.isPastDue, isTrue);
      expect(sub.isActive, isFalse);
      expect(sub.graceEndsAt, DateTime.utc(2026, 10, 8, 10));
      // The offline cache round-trips it.
      final again = SubscriptionInfo.fromJson(sub.toJson());
      expect(again.expiresAt, sub.expiresAt);
      expect(again.graceEndsAt, sub.graceEndsAt);
    });

    test('past_due texts', () {
      final sub = SubscriptionInfo(status: 'past_due', graceEndsAt: DateTime(2026, 10, 8, 12));
      expect(renewBeforeLine(sub, kRussianStrings), 'Продлите до 08.10.2026');
      expect(subscriptionStatusLabel(sub, kRussianStrings), 'Ожидает продления');
      expect(renewBeforeLine(const SubscriptionInfo(status: 'past_due'), kRussianStrings), kRussianStrings.renewResetNote);
    });
  });

  group('traffic units', () {
    test('binary ГБ, same base as Core plan limits', () {
      expect(formatTraffic(107374182400 ~/ 10, 107374182400, kRussianStrings), '10 ГБ / 100 ГБ');
      expect(formatTraffic(1610612736, null, kRussianStrings), '1.5 ГБ / ${kRussianStrings.trafficUnlimited}');
      expect(formatTraffic(0, 107374182400, kEnglishStrings), '0 MB / 100 GB');
      // Small usage stays visible instead of rounding to "0 ГБ".
      expect(formatTraffic(327155712, 322122547200, kRussianStrings), '312 МБ / 300 ГБ');
      expect(formatTraffic(5452595, 322122547200, kRussianStrings), '5.2 МБ / 300 ГБ');
      expect(formatTraffic(1073741823, null, kRussianStrings), '1 ГБ / ${kRussianStrings.trafficUnlimited}');
    });
  });
}
