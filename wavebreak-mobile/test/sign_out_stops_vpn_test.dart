import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/core/auth/session_controller.dart';
import 'package:wavebreak/features/shared/data_providers.dart';
import 'package:wavebreak/services/vpn/connection_manager.dart';

import 'test_helpers.dart';

/// Signing out ends the VPN: before, the tunnel kept carrying traffic
/// after sign-out and its old start time came back after the next sign-in.
void main() {
  setUp(setUpTestEnvironment);

  Future<ProviderContainer> connected() async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    await container.read(locationsProvider.future);
    await container
        .read(connectionManagerProvider.notifier)
        .connect(subscriptionActive: true);
    expect(container.read(connectionManagerProvider).status,
        ConnectionStatus.connected);
    return container;
  }

  test('signing out disconnects the VPN', () async {
    final container = await connected();
    addTearDown(container.dispose);

    await container.read(sessionControllerProvider.notifier).logout();

    final state = container.read(connectionManagerProvider);
    expect(state.status, ConnectionStatus.idle);
    expect(state.connectedAt, isNull);
  });

  test('a session ended by Core disconnects the VPN too', () async {
    final container = await connected();
    addTearDown(container.dispose);

    await container.read(sessionControllerProvider.notifier).forceLogout();

    final state = container.read(connectionManagerProvider);
    expect(state.status, ConnectionStatus.idle);
    expect(state.connectedAt, isNull);
  });

  test('signing out while idle leaves it idle', () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);

    await container.read(sessionControllerProvider.notifier).logout();

    expect(container.read(connectionManagerProvider).status,
        ConnectionStatus.idle);
  });
}
