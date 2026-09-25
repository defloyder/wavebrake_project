import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/services/core_api/models.dart';
import 'package:wavebreak/services/vpn/connection_manager.dart';
import 'package:wavebreak/services/vpn/speed_test_controller.dart';

import 'test_helpers.dart';

// Regression coverage for a real-device bug: switching to a different
// location and running the speed test again showed the PREVIOUS
// connection's numbers instead of starting fresh. The fix is
// SpeedTestController watching the active connection's location and
// resetting whenever it actually changes — this test drives that
// directly rather than through a real network probe (SpeedTestService
// itself isn't exercised here; that needs a real socket).
void main() {
  setUp(setUpTestEnvironment);

  test('switching location resets a finished speed test result', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Establish the watch dependency on connectionManagerProvider's
    // location before changing it — same as any real widget watching
    // this provider would.
    container.read(speedTestControllerProvider);

    // Simulate a finished test, the way SpeedTestController.run() itself
    // would land on `done` — this is what "stale data from the previous
    // measurement" looked like on-device.
    container.read(speedTestControllerProvider.notifier).state =
        const SpeedTestState(
      status: SpeedTestStatus.done,
      downloadMbps: 123.4,
      uploadMbps: 56.7,
    );
    expect(
      container.read(speedTestControllerProvider).status,
      SpeedTestStatus.done,
    );

    // Switching to a different location is exactly the trigger the bug
    // report described.
    container.read(connectionManagerProvider.notifier).selectLocation(
          const LocationItem(
            id: 'a-different-location',
            countryCode: 'TR',
            country: 'Turkey',
            city: 'Istanbul',
            available: true,
          ),
        );

    final afterSwitch = container.read(speedTestControllerProvider);
    expect(afterSwitch.status, SpeedTestStatus.idle,
        reason: 'a location switch must reset a finished result, not '
            'leave the previous connection\'s numbers on screen');
    expect(afterSwitch.downloadMbps, isNull);
    expect(afterSwitch.uploadMbps, isNull);
  });

  test('reselecting the SAME location does not reset an in-progress result',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(speedTestControllerProvider);
    final currentLocation =
        container.read(connectionManagerProvider).location;

    container.read(speedTestControllerProvider.notifier).state =
        const SpeedTestState(
      status: SpeedTestStatus.done,
      downloadMbps: 99.0,
      uploadMbps: 12.0,
    );

    // Re-selecting the exact same location (e.g. re-tapping the current
    // server in the picker) is not a "switch" and must not blow away a
    // result the user just measured for it.
    container
        .read(connectionManagerProvider.notifier)
        .selectLocation(currentLocation);

    final state = container.read(speedTestControllerProvider);
    expect(state.status, SpeedTestStatus.done);
    expect(state.downloadMbps, 99.0);
  });
}
