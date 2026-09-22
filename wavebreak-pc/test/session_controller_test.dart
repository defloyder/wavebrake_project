import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/core/auth/session_controller.dart';
import 'package:wavebreak/services/core_api/mock_backend.dart';
import 'package:wavebreak/services/providers.dart';

import 'test_helpers.dart';

void main() {
  setUp(setUpTestEnvironment);

  test('login succeeds with valid credentials and reaches authenticated', () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);

    final tokens = await container
        .read(coreGatewayProvider)
        .login(email: 'user@wavebreak.app', password: 'password1');
    await container.read(sessionControllerProvider.notifier).onAuthenticated(tokens);

    expect(
      container.read(sessionControllerProvider).phase,
      SessionPhase.authenticated,
    );
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
    await container.read(sessionControllerProvider.notifier).onAuthenticated(tokens);

    final refreshed =
        await container.read(sessionControllerProvider.notifier).refreshTokens();

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
    await container.read(sessionControllerProvider.notifier).onAuthenticated(tokens);

    final refreshed =
        await container.read(sessionControllerProvider.notifier).refreshTokens();
    expect(refreshed, isFalse);
  });

  test('logout clears session', () async {
    final container = ProviderContainer(overrides: mockCoreOverrides());
    addTearDown(container.dispose);

    final tokens = await container.read(coreGatewayProvider).login(
          email: 'user@wavebreak.app',
          password: 'password1',
        );
    await container.read(sessionControllerProvider.notifier).onAuthenticated(tokens);
    await container.read(sessionControllerProvider.notifier).logout();

    expect(
      container.read(sessionControllerProvider).phase,
      SessionPhase.unauthenticated,
    );
    expect(container.read(sessionControllerProvider).user, isNull);
  });
}
