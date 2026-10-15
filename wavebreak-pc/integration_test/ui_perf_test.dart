// The real Windows app (mock Core, in-memory storage — nothing of an
// installed WAVEBREAK is touched) timed in profile mode: frames while it
// sits on Home, and while the user switches tabs and opens settings pages
// (owner, 15.10: "buttons and forms switch slowly, as if lagging").
//
//   flutter drive --profile -d windows --driver=test_driver/perf_driver.dart --target=integration_test/ui_perf_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavebreak/app/app.dart';
import 'package:wavebreak/app/router.dart';
import 'package:wavebreak/core/storage/prefs_store.dart';
import 'package:wavebreak/core/storage/secure_store.dart';
import 'package:wavebreak/services/core_api/mock_backend.dart';

import '../test/test_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('UI frame timings', (tester) async {
    await setUpTestEnvironment();
    await PrefsStore.setBool(PrefsStore.onboardingChoiceMade, true);
    await PrefsStore.setString(PrefsStore.language, 'ru');
    await SecureStore.write(SecureStore.accessToken, 'mock-access');
    await SecureStore.write(SecureStore.refreshToken, 'mock-refresh');

    await tester.pumpWidget(ProviderScope(
      overrides: mockCoreOverrides(MockCoreBackend()),
      child: const WavebreakApp(),
    ));
    await tester.pump(const Duration(seconds: 3));
    final router =
        ProviderScope.containerOf(tester.element(find.byType(WavebreakApp)))
            .read(routerProvider);

    Future<void> wait(int ms) => tester.pump(Duration(milliseconds: ms));

    // Sitting on Home: what the animated background and glass cost.
    await binding.traceAction(() async {
      for (var i = 0; i < 40; i++) {
        await wait(100);
      }
    }, reportKey: 'idle_home');

    // Switching sections and opening pages, as a user clicks through.
    await binding.traceAction(() async {
      for (var round = 0; round < 3; round++) {
        for (final path in [
          '/locations',
          '/settings',
          '/settings/connection',
          '/settings',
          '/speed-test',
          '/metrics',
          '/home',
        ]) {
          router.go(path);
          for (var i = 0; i < 6; i++) {
            await wait(50);
          }
        }
      }
    }, reportKey: 'navigation');
  });
}
