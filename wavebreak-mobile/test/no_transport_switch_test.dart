import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/features/shared/data_providers.dart';
import 'package:wavebreak/services/core_api/models.dart';
import 'package:wavebreak/services/custom_servers/share_link_parsing.dart';
import 'package:wavebreak/services/vpn/connection_manager.dart';
import 'package:wavebreak/services/vpn/vpn_adapter.dart';

import 'test_helpers.dart';

const _g = '11111111-2222-4333-8444-555555555555';
const _hysteria = 'hysteria2://$_g@45.15.41.3:443/?alpn=h3&sni=hy2.example.test#Turkey%2C%20Istanbul%20%28Hysteria2%29';
const _direct = 'vless://$_g@direct.example.test:443?encryption=none&security=tls&type=ws&sni=direct.example.test#Turkey%2C%20Istanbul%20%28Direct-TLS%29';
const _reality = 'vless://$_g@45.15.41.3:443?encryption=none&security=reality&type=tcp&sni=r.example.test#Turkey%2C%20Istanbul%20%28VLESS%29';

/// Connects instantly unless the link is one this "network" blocks.
class _CarrierAdapter implements VpnAdapter {
  _CarrierAdapter(this.blocked);

  final Set<String> blocked;
  final attempts = <String>[];
  final _states = StreamController<VpnNativeState>.broadcast();

  @override
  Stream<VpnNativeState> get states => _states.stream;

  @override
  Future<void> connect(ConnectionProfile profile) async {
    final link = profile.rawJson;
    attempts.add(link.split('://').first);
    if (blocked.any(link.contains)) {
      _states.add(VpnNativeState.failed);
      throw StateError('handshake failed');
    }
    _states.add(VpnNativeState.connected);
  }

  @override
  Future<void> disconnect() async => _states.add(VpnNativeState.idle);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(setUpTestEnvironment);

  ProviderContainer containerWith(_CarrierAdapter adapter) {
    final personal = parseSubscriptionBody([_reality, _direct, _hysteria].join('\n'));
    final c = ProviderContainer(overrides: [
      ...mockCoreOverrides(),
      locationsProvider.overrideWith((ref) async => personal),
      vpnAdapterProvider.overrideWithValue(adapter),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  // The automatic transport fallback was removed at the owner's request:
  // on a flaky network it hopped between locations by itself and the
  // home screen jumped with it. The app stays on what the user picked.
  test('a transport this network blocks is an error; no other transport is tried', () async {
    final adapter = _CarrierAdapter({'hysteria2://'});
    final c = containerWith(adapter);
    final personal = await c.read(locationsProvider.future);
    final hysteria = personal.firstWhere((l) => l.rawLink == _hysteria);

    await c.read(connectionManagerProvider.notifier).selectLocation(hysteria);
    await c.read(connectionManagerProvider.notifier).connect(subscriptionActive: true);

    final state = c.read(connectionManagerProvider);
    expect(state.status, ConnectionStatus.error);
    expect(adapter.attempts, ['hysteria2']);
    expect(state.location.rawLink, _hysteria, reason: 'the pick stays selected');
  });

  test('a working pick stays the pick', () async {
    final adapter = _CarrierAdapter({});
    final c = containerWith(adapter);
    final personal = await c.read(locationsProvider.future);
    final direct = personal.firstWhere((l) => l.rawLink == _direct);

    await c.read(connectionManagerProvider.notifier).selectLocation(direct);
    await c.read(connectionManagerProvider.notifier).connect(subscriptionActive: true);

    final state = c.read(connectionManagerProvider);
    expect(state.status, ConnectionStatus.connected);
    expect(adapter.attempts, ['vless']);
    expect(state.location.rawLink, _direct);
  });

  test("a user's own server is never swapped for another", () async {
    final adapter = _CarrierAdapter({'hysteria2://'});
    final c = containerWith(adapter);
    await c.read(locationsProvider.future);
    final own = parseSubscriptionBody('hysteria2://x@198.51.100.1:443/?sni=own.test#Mine').single;

    await c.read(connectionManagerProvider.notifier).selectLocation(own);
    await c.read(connectionManagerProvider.notifier).connect(subscriptionActive: true);

    expect(c.read(connectionManagerProvider).status, ConnectionStatus.error);
    expect(adapter.attempts, ['hysteria2']);
  });
}
