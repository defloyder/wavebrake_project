// fake_async comes with flutter_test.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/features/shared/data_providers.dart';
import 'package:wavebreak/services/core_api/models.dart';
import 'package:wavebreak/services/custom_servers/custom_server_controller.dart';
import 'package:wavebreak/services/custom_servers/custom_subscription.dart';
import 'package:wavebreak/services/server_list_refresher.dart';

import 'test_helpers.dart';

class _CountingServers extends CustomServerController {
  int refreshes = 0;

  @override
  List<CustomSubscriptionGroup> build() => const [];

  @override
  Future<void> refreshAll() async => refreshes++;
}

void main() {
  setUp(setUpTestEnvironment);

  test('server lists are read again every 30 minutes, not sooner', () {
    fakeAsync((async) {
      var locationReads = 0;
      final servers = _CountingServers();
      final container = ProviderContainer(overrides: [
        customServersProvider.overrideWith(() => servers),
        locationsProvider.overrideWith((ref) async {
          locationReads++;
          return const <LocationItem>[];
        }),
      ]);
      addTearDown(container.dispose);
      // Something on screen watches the list.
      container.listen(locationsProvider, (_, __) {});
      async.flushMicrotasks();
      expect(locationReads, 1);

      container.read(serverListRefresherProvider).start();
      async.elapse(const Duration(minutes: 29));
      container.read(locationsProvider);
      async.flushMicrotasks();
      expect(locationReads, 1);
      expect(servers.refreshes, 0);

      async.elapse(const Duration(minutes: 1));
      container.read(locationsProvider);
      async.flushMicrotasks();
      expect(locationReads, 2);
      expect(servers.refreshes, 1);

      async.elapse(serverListRefreshEvery);
      container.read(locationsProvider);
      async.flushMicrotasks();
      expect(locationReads, 3);
      expect(servers.refreshes, 2);

      // Started twice: still one timer.
      container.read(serverListRefresherProvider).start();
      async.elapse(serverListRefreshEvery);
      expect(servers.refreshes, 3);
    });
  });
}
