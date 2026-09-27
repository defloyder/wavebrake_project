import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/core/errors/app_exception.dart';
import 'package:wavebreak/core/errors/error_mapper.dart';
import 'package:wavebreak/core/i18n/app_strings.dart';
import 'package:wavebreak/features/shared/subscription_section.dart';
import 'package:wavebreak/services/core_api/core_gateway.dart';
import 'package:wavebreak/services/core_api/models.dart';
import 'package:wavebreak/services/custom_servers/custom_server_controller.dart';
import 'package:wavebreak/services/custom_servers/custom_subscription.dart';
import 'package:wavebreak/services/custom_servers/share_link_parsing.dart';
import 'package:wavebreak/services/providers.dart';
import 'package:wavebreak/services/vpn/connection_manager.dart';
import 'package:wavebreak/services/vpn/vpn_adapter.dart';

import 'test_helpers.dart';

const _token = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIj';
const _credential = '11111111-2222-4333-8444-555555555555';
const _links = [
  'vless://$_credential@45.15.41.3:443?encryption=none&flow=xtls-rprx-vision&fp=chrome'
      '&pbk=test-key&security=reality&sid=ab12&sni=r.example.test&type=tcp'
      '#%F0%9F%87%B9%F0%9F%87%B7%20Turkey%2C%20Istanbul%20%28VLESS%29',
  'hysteria2://$_credential@45.15.41.3:443/?alpn=h3&sni=hy2.example.test'
      '#%F0%9F%87%B9%F0%9F%87%B7%20Turkey%2C%20Istanbul%20%28Hysteria2%29',
];

/// Only redeemShare() matters here; anything else is a test bug.
class _FakeGateway implements CoreGateway {
  _FakeGateway(this.answer);

  Future<SharedAccess> Function() answer;
  int calls = 0;
  String? lastToken;

  SharingOverview overview = SharingOverview.empty;

  @override
  Future<SharingOverview> sharing() async => overview;

  @override
  Future<SharedAccess> redeemShare({
    required String token,
    required String deviceName,
    required String platform,
  }) {
    calls++;
    lastToken = token;
    return answer();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppException _mapped(int status, String code) => const ErrorMapper().map(DioException(
      requestOptions: RequestOptions(path: '/share/redeem', headers: {'Authorization': 'Bearer x'}),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/share/redeem'),
        statusCode: status,
        data: {
          'error': {'code': code, 'message': 'm'},
        },
      ),
    ));

List<Override> _overrides(_FakeGateway gateway) => [
      coreGatewayProvider.overrideWithValue(gateway),
      vpnAdapterProvider.overrideWithValue(SimulatedVpnAdapter(delay: Duration.zero)),
    ];

void main() {
  test('share code detection: only /v1/share/<48-char token>', () {
    expect(wavebreakShareToken('https://core.wavebreak.com.tr/v1/share/$_token'), _token);
    expect(wavebreakShareToken('  https://api.example.test/v1/share/$_token '), _token);
    expect(wavebreakShareToken('https://core.wavebreak.com.tr/v1/sub/$_credential'), isNull);
    expect(wavebreakShareToken('https://core.wavebreak.com.tr/v1/share/short'), isNull);
    expect(wavebreakShareToken('https://core.wavebreak.com.tr/v1/share/$_token/x'), isNull);
    expect(wavebreakShareToken('vless://$_credential@h:443#x'), isNull);
    expect(wavebreakShareToken('ftp://h/v1/share/$_token'), isNull);
  });

  test('ShareInfo parses limits; slotsFull only with a limit reached', () {
    final info = ShareInfo.fromJson({
      'share_url': 'https://core.example.test/v1/share/$_token',
      'expires_at': '2026-10-01T00:00:00Z',
      'limits': {'device_limit': 3, 'devices_used': 3, 'traffic_limit_bytes': 1073741824, 'traffic_used_bytes': 5},
    });
    expect(info.shareUrl, endsWith(_token));
    expect(info.deviceLimit, 3);
    expect(info.trafficLimitBytes, 1073741824);
    expect(info.slotsFull, isTrue);
    expect(ShareInfo.fromJson({'share_url': 'u', 'limits': {'device_limit': null, 'devices_used': 9}}).slotsFull, isFalse);
  });

  test('share error codes map onto their own kinds', () {
    expect(_mapped(410, 'SHARE_EXPIRED').kind, AppErrorKind.shareInvalid);
    expect(_mapped(400, 'SHARE_INVALID').kind, AppErrorKind.shareInvalid);
    expect(_mapped(409, 'SHARE_OWN_SUBSCRIPTION').kind, AppErrorKind.shareOwnSubscription);
    expect(_mapped(403, 'DEVICE_LIMIT_REACHED').kind, AppErrorKind.deviceLimitReached);
    final inactive = _mapped(422, 'SUBSCRIPTION_NOT_ACTIVE');
    expect(inactive.statusCode, 422);
  });

  test('sections: own subscription shares a fresh code; a redeemed one is never re-shared', () {
    final sections = buildSubscriptionSections(
      wavebreakLocations: const [],
      customGroups: const [
        CustomSubscriptionGroup(id: 'a', name: 'Mine', sourceLink: 'https://x.test/sub', servers: []),
        CustomSubscriptionGroup(id: 'b', name: 'Shared', sourceLink: 'https://core.test/v1/sub/1', servers: [], sharedWithMe: true),
      ],
      s: kRussianStrings,
      sharing: const SharingOverview(
        own: SharedSubscription(planName: 'Fleet', status: 'active', deviceLimit: 2, devicesUsed: 1),
        received: [
          SharedSubscription(subscriptionUrl: 'https://core.test/v1/sub/1', status: 'past_due'),
        ],
      ),
    );
    expect(sections[0].title, 'WAVEBREAK Fleet');
    expect(sections[0].limitsDevices, '1 / 2');
    expect(sections[0].limitsTraffic, isNotNull);
    expect(sections[1].limitsTraffic, isNull);
    expect(sections[2].limitsNote, kRussianStrings.shareOwnerInactive);
    expect(sections[2].limitsTraffic, isNull);
    expect(sections[0].shareLink, kPersonalShareLink);
    expect(sections[1].shareLink, 'https://x.test/sub');
    expect(sections[1].shareable, isTrue);
    expect(sections[2].shareLink, isNull);
    expect(sections[2].shareable, isFalse);
  });

  group('redeeming a scanned share code', () {
    late _FakeGateway gateway;
    late ProviderContainer container;

    setUp(() async {
      await setUpTestEnvironment();
      gateway = _FakeGateway(() async => const SharedAccess(
            links: _links,
            planName: 'Plus',
            subscriptionUrl: 'https://core.example.test/v1/sub/$_credential',
          ));
      container = ProviderContainer(overrides: _overrides(gateway));
      addTearDown(container.dispose);
    });

    test('adds one shared section, rescanning refreshes it, and it survives a restart', () async {
      final notifier = container.read(customServersProvider.notifier);
      expect(await notifier.addFromLink('https://core.example.test/v1/share/$_token'), isNull);
      expect(gateway.lastToken, _token);
      var groups = container.read(customServersProvider);
      expect(groups, hasLength(1));
      expect(groups.single.name, 'WAVEBREAK Plus');
      expect(groups.single.sharedWithMe, isTrue);
      expect(groups.single.sourceLink, 'https://core.example.test/v1/sub/$_credential');
      expect(groups.single.servers, hasLength(2));

      expect(await notifier.addFromLink('https://core.example.test/v1/share/$_token'), isNull);
      expect(container.read(customServersProvider), hasLength(1));

      // A fresh controller reads the saved list back, flag included.
      final reloaded = ProviderContainer(overrides: _overrides(gateway));
      addTearDown(reloaded.dispose);
      groups = reloaded.read(customServersProvider);
      expect(groups.single.sharedWithMe, isTrue);
    });

    test('Core refusals become the sheet\'s error codes', () async {
      final notifier = container.read(customServersProvider.notifier);
      final cases = {
        AppException(AppErrorKind.deviceLimitReached, statusCode: 403): 'share_limit',
        AppException(AppErrorKind.shareInvalid, statusCode: 410): 'share_invalid',
        AppException(AppErrorKind.shareOwnSubscription, statusCode: 409): 'share_own',
        AppException(AppErrorKind.unavailable, statusCode: 422): 'share_inactive',
        AppException(AppErrorKind.unavailable, statusCode: 404): 'share_inactive',
        AppException(AppErrorKind.unavailable): 'unreachable',
      };
      for (final entry in cases.entries) {
        gateway.answer = () => Future.error(entry.key);
        expect(await notifier.addFromLink('https://core.example.test/v1/share/$_token'), entry.value);
      }
      expect(container.read(customServersProvider), isEmpty);
    });

    test('sync: plan name and app links from Core; a revoked slot drops the section', () async {
      final notifier = container.read(customServersProvider.notifier);
      expect(await notifier.addFromLink('https://core.example.test/v1/share/$_token'), isNull);
      final url = 'https://core.example.test/v1/sub/$_credential';

      // Refresh goes through Core (no CDN, no host as the name).
      gateway.overview = SharingOverview(received: [
        SharedSubscription(planName: 'Fleet', status: 'active', subscriptionUrl: url, links: [_links.last]),
      ]);
      await notifier.refreshGroup(container.read(customServersProvider).single.id);
      var group = container.read(customServersProvider).single;
      expect(group.name, 'WAVEBREAK Fleet');
      expect(group.servers, hasLength(1));
      expect(group.sharedWithMe, isTrue);

      // Owner's subscription inactive: links kept as they were.
      await notifier.syncShared(SharingOverview(received: [
        SharedSubscription(planName: 'Fleet', status: 'past_due', subscriptionUrl: url),
      ]));
      group = container.read(customServersProvider).single;
      expect(group.servers, hasLength(1));

      // Right after a scan an overview without the new slot is stale, not
      // a revocation.
      await notifier.syncShared(SharingOverview.empty);
      expect(container.read(customServersProvider), hasLength(1));

      // Owner revoked the slot: gone.
      notifier.forgetRecentRedeems();
      await notifier.syncShared(SharingOverview.empty);
      expect(container.read(customServersProvider), isEmpty);
    });

    test('sync never touches the user\'s own links', () async {
      final notifier = container.read(customServersProvider.notifier);
      expect(await notifier.addFromLink(_links.first), isNull);
      await notifier.syncShared(SharingOverview.empty);
      expect(container.read(customServersProvider), hasLength(1));
    });

    test('a non-share link never reaches Core', () async {
      final notifier = container.read(customServersProvider.notifier);
      expect(await notifier.addFromLink(_links.first), isNull);
      expect(gateway.calls, 0);
      expect(container.read(customServersProvider).single.sharedWithMe, isFalse);
    });
  });
}
