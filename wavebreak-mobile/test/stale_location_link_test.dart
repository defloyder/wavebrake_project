import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/services/custom_servers/share_link_parsing.dart';
import 'package:wavebreak/services/vpn/connection_manager.dart';

import 'test_helpers.dart';

void main() {
  setUp(setUpTestEnvironment);

  // 01.10: the server moved Hysteria from port 44100 to 443. The link —
  // and with it the location id, a hash of the link — changed, and the
  // app kept connecting with the old one.
  test('a selected location whose link changed on the server gets the new link',
      () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);
    final manager = container.read(connectionManagerProvider.notifier);

    final old = parseSubscriptionBody(
            'hysteria2://pw@45.15.41.3:44100?sni=hy2.example#Турция Hysteria2')
        .single;
    final fresh = parseSubscriptionBody(
            'hysteria2://pw@45.15.41.3:443?sni=hy2.example&cloak=1#Турция Hysteria2')
        .single;
    final other = parseSubscriptionBody(
            'vless://id@45.15.41.3:8443?security=tls#Турция Direct')
        .single;
    expect(fresh.id, isNot(old.id));

    await manager.selectLocation(old);
    manager.hydrateLocations([other, fresh]);

    final selected = container.read(connectionManagerProvider).location;
    expect(selected.id, fresh.id);
    expect(selected.rawLink, contains(':443'));
  });

  test('no guessing when two locations share the name', () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);
    final manager = container.read(connectionManagerProvider.notifier);

    final old =
        parseSubscriptionBody('hysteria2://a@h:1#Турция Hysteria2').single;
    final twins = parseSubscriptionBody(
        'hysteria2://b@h:2#Турция Hysteria2\nhysteria2://c@h:3#Турция Hysteria2');

    await manager.selectLocation(old);
    manager.hydrateLocations(twins);

    expect(container.read(connectionManagerProvider).location.id, old.id);
  });
}
