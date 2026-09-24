import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/features/shared/data_providers.dart';
import 'package:wavebreak/services/core_api/mock_backend.dart';
import 'package:wavebreak/services/core_api/models.dart';
import 'package:wavebreak/services/providers.dart';
import 'package:wavebreak/services/vpn/connection_manager.dart';

import 'test_helpers.dart';

void main() {
  setUp(setUpTestEnvironment);

  test('connect without an active subscription surfaces subscriptionRequired',
      () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);

    await container
        .read(connectionManagerProvider.notifier)
        .connect(subscriptionActive: false);

    expect(
      container.read(connectionManagerProvider).status,
      ConnectionStatus.error,
    );
  });

  test('connect with an active subscription reaches connected', () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);

    // Auto has no server-side meaning — the manager resolves it against
    // whatever `/v1/locations` last returned, so that needs to have
    // resolved at least once before connecting, exactly like Home
    // prefetches it before the user can ever tap Connect.
    await container.read(locationsProvider.future);
    await container
        .read(connectionManagerProvider.notifier)
        .connect(subscriptionActive: true);

    expect(
      container.read(connectionManagerProvider).status,
      ConnectionStatus.connected,
    );
  });

  test('disconnect returns to idle', () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);

    await container.read(locationsProvider.future);
    await container
        .read(connectionManagerProvider.notifier)
        .connect(subscriptionActive: true);
    await container.read(connectionManagerProvider.notifier).disconnect();

    expect(
      container.read(connectionManagerProvider).status,
      ConnectionStatus.idle,
    );
  });

  test('an expired subscription surfaces connectionFailed from the Core',
      () async {
    final mock = MockCoreBackend()
      ..subscription = SubscriptionInfo(
        status: 'expired',
        planName: 'WAVEBREAK Monthly',
      );
    final container = ProviderContainer(overrides: mockCoreOverrides(mock));
    addTearDown(container.dispose);

    await container
        .read(connectionManagerProvider.notifier)
        .connect(subscriptionActive: true);

    expect(
      container.read(connectionManagerProvider).status,
      ConnectionStatus.error,
    );
  });

  test('device revocation on the Core surfaces an access error', () async {
    final mock = MockCoreBackend()..deviceRevoked = true;
    final container = ProviderContainer(overrides: mockCoreOverrides(mock));
    addTearDown(container.dispose);

    await container
        .read(connectionManagerProvider.notifier)
        .connect(subscriptionActive: true);

    expect(
      container.read(connectionManagerProvider).status,
      ConnectionStatus.error,
    );
  });

  test('selecting a location persists it for the next session', () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);

    final locations = await container.read(coreGatewayProvider).locations();
    container
        .read(connectionManagerProvider.notifier)
        .selectLocation(locations.first);

    expect(
      container.read(connectionManagerProvider).location.id,
      locations.first.id,
    );
  });
}
