import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/core/auth/session_controller.dart';
import 'package:wavebreak/services/core_api/mock_backend.dart';
import 'package:wavebreak/services/providers.dart';

import 'test_helpers.dart';

void main() {
  setUp(setUpTestEnvironment);

  test('login succeeds with valid credentials and reaches authenticated',
      () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);

    final tokens = await container
        .read(coreGatewayProvider)
        .login(email: 'user@wavebreak.app', password: 'password1');
    await container
        .read(sessionControllerProvider.notifier)
        .onAuthenticated(tokens);

    expect(
      container.read(sessionControllerProvider).phase,
      SessionPhase.authenticated,
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(sessionControllerProvider).user?.email,
      'user@wavebreak.app',
    );
  });

  test('login fails with invalid credentials', () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);

    expect(
      () => container
          .read(coreGatewayProvider)
          .login(email: 'user@wavebreak.app', password: 'short'),
      throwsA(isA<Exception>()),
    );
  });

  test('bootstrapSession is unauthenticated with no stored session', () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);

    await container.read(sessionControllerProvider.notifier).bootstrapSession();

    expect(
      container.read(sessionControllerProvider).phase,
      SessionPhase.unauthenticated,
    );
  });

  test('token refresh restores authenticated session after 401', () async {
    final mock = MockCoreBackend();
    final container = ProviderContainer(overrides: mockCoreOverrides(mock));
    addTearDown(container.dispose);

    final tokens = await container.read(coreGatewayProvider).login(
          email: 'user@wavebreak.app',
          password: 'password1',
        );
    await container
        .read(sessionControllerProvider.notifier)
        .onAuthenticated(tokens);

    final refreshed = await container
        .read(sessionControllerProvider.notifier)
        .refreshTokens();

    expect(refreshed, isTrue);
  });

  test('failed refresh forces logout', () async {
    final mock = MockCoreBackend()..refreshShouldFail = true;
    final container = ProviderContainer(overrides: mockCoreOverrides(mock));
    addTearDown(container.dispose);

    final tokens = await container.read(coreGatewayProvider).login(
          email: 'user@wavebreak.app',
          password: 'password1',
        );
    await container
        .read(sessionControllerProvider.notifier)
        .onAuthenticated(tokens);

    final refreshed = await container
        .read(sessionControllerProvider.notifier)
        .refreshTokens();
    expect(refreshed, isFalse);
    expect(
      container.read(sessionControllerProvider).phase,
      SessionPhase.unauthenticated,
      reason: 'Core genuinely rejecting the refresh token must end the session',
    );
  });

  // Regression coverage for a real-device bug: "occasionally logs the
  // user out unexpectedly" / "heavily dependent on WiFi." A transient
  // network failure DURING the refresh call itself (unlike Core actually
  // rejecting the refresh token, covered above) must not end a perfectly
  // good session.
  test('a transient refresh failure does not force logout', () async {
    final mock = MockCoreBackend()..refreshShouldFailTransiently = true;
    final container = ProviderContainer(overrides: mockCoreOverrides(mock));
    addTearDown(container.dispose);

    final tokens = await container.read(coreGatewayProvider).login(
          email: 'user@wavebreak.app',
          password: 'password1',
        );
    await container
        .read(sessionControllerProvider.notifier)
        .onAuthenticated(tokens);
    expect(
      container.read(sessionControllerProvider).phase,
      SessionPhase.authenticated,
    );

    final refreshed = await container
        .read(sessionControllerProvider.notifier)
        .refreshTokens();
    expect(refreshed, isFalse,
        reason: 'the refresh attempt itself still failed, so no new token');
    expect(
      container.read(sessionControllerProvider).phase,
      SessionPhase.authenticated,
      reason: 'a network hiccup during refresh must not end the session',
    );
  });

  test('logout clears session', () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);

    final tokens = await container.read(coreGatewayProvider).login(
          email: 'user@wavebreak.app',
          password: 'password1',
        );
    await container
        .read(sessionControllerProvider.notifier)
        .onAuthenticated(tokens);
    await container.read(sessionControllerProvider.notifier).logout();

    expect(
      container.read(sessionControllerProvider).phase,
      SessionPhase.unauthenticated,
    );
    expect(container.read(sessionControllerProvider).user, isNull);
  });
}
