import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/features/speedtest/speed_test_screen.dart';
import 'package:wavebreak/services/vpn/speed_test_controller.dart';

import 'test_helpers.dart';

/// A fixed-state stand-in for the real controller — the redesign this
/// covers (idle -> testing-latency -> testing-download -> testing-upload
/// -> done/failed all rendering distinctly, see wave_meter.dart and
/// speed_test_screen.dart) is a UI/rendering concern, not a state-machine
/// one (that's already covered by speed_test_controller_test.dart), so
/// this drives the screen off an arbitrary fixed [SpeedTestState] rather
/// than a real SpeedTestService network call.
class _FixedSpeedTestController extends SpeedTestController {
  _FixedSpeedTestController(this._fixed);
  final SpeedTestState _fixed;

  @override
  SpeedTestState build() => _fixed;
}

Future<void> _pumpWithState(
  WidgetTester tester,
  SpeedTestState state,
) async {
  // The default 800x600 test surface is shorter than this screen's
  // content (a square wave meter plus a stepper, result cards, and the
  // action button below it) — plenty of real phones are taller than
  // that too, but the point here is making sure `find.text` can actually
  // see everything being asserted on rather than fighting the test
  // viewport's own size. A tall, narrow surface matches a real phone's
  // proportions and gives every element in the ListView room to lay out.
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // A fresh key each call — reusing the same ProviderScope element across
  // pumpWidget calls in the same test keeps its already-built container
  // (and the notifier instance built the first time) instead of picking
  // up the new override, which silently made every subsequent state in a
  // multi-state test look identical to the first. A new key forces
  // Flutter to tear down and rebuild the whole subtree, container
  // included.
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        speedTestControllerProvider
            .overrideWith(() => _FixedSpeedTestController(state)),
      ],
      child: const MaterialApp(home: SpeedTestScreen()),
    ),
  );
  // The wave meter's own motion is driven by a repeating
  // AnimationController (see wave_meter.dart) — a single pump is enough
  // to read the static text/icon content this test actually checks,
  // without needing to settle a continuously-repeating animation (which
  // pumpAndSettle would never do).
  await tester.pump();
}

void main() {
  setUp(setUpTestEnvironment);

  testWidgets(
      'idle renders the idle hint and a placeholder reading, not a stale number',
      (tester) async {
    await _pumpWithState(tester, const SpeedTestState());

    expect(find.text('Tap Start to measure your connection'), findsOneWidget);
    expect(find.text('Start test'), findsOneWidget);
  });

  testWidgets(
      'testing-latency names latency specifically, not a generic "running" label',
      (tester) async {
    await _pumpWithState(
      tester,
      const SpeedTestState(status: SpeedTestStatus.testingLatency),
    );

    expect(find.text('Testing latency'), findsWidgets);
  });

  testWidgets(
      'testing-download and testing-upload render distinct phase labels',
      (tester) async {
    await _pumpWithState(
      tester,
      const SpeedTestState(
        status: SpeedTestStatus.testingDownload,
        liveMbps: 42.5,
        progress: 0.5,
      ),
    );
    expect(find.text('Testing download'), findsWidgets);
    expect(find.text('Testing upload'), findsNothing);

    await _pumpWithState(
      tester,
      const SpeedTestState(
        status: SpeedTestStatus.testingUpload,
        downloadMbps: 42.5,
        liveMbps: 10.2,
        progress: 0.3,
      ),
    );
    expect(find.text('Testing upload'), findsWidgets);
    expect(find.text('Testing download'), findsNothing);
    // Regression coverage for a real-device bug: the download summary
    // tile stayed on "–" through the entire upload leg even though
    // download's own real number had been known since the moment it
    // finished — SpeedTestController now surfaces each leg's result via
    // SpeedTestService.run's onLegDone the instant that leg completes,
    // not only once the whole two-leg run() resolves. Mid-upload here
    // (downloadMbps already set on the fixed state, matching what
    // onLegDone would have written) must show the real number already.
    expect(find.text('42.5 Mbps'), findsOneWidget);
  });

  testWidgets(
      'done renders a distinct completion state with a settle checkmark',
      (tester) async {
    await _pumpWithState(
      tester,
      const SpeedTestState(
        status: SpeedTestStatus.done,
        latencyMs: 24,
        downloadMbps: 88.4,
        uploadMbps: 21.1,
      ),
    );

    expect(find.text('Test complete'), findsOneWidget);
    expect(find.text('Test again'), findsOneWidget);
    // The settle checkmark inside the meter, plus one per completed step
    // in the stepper (latency/download/upload all landed a real value) —
    // done is visually distinguished by more than the number simply
    // holding still.
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('failed renders a distinct failure state, not a silent "done"',
      (tester) async {
    await _pumpWithState(
      tester,
      const SpeedTestState(status: SpeedTestStatus.failed),
    );

    expect(
      find.text(
          'Could not complete the test — check your connection and try again'),
      findsOneWidget,
    );
    expect(find.text('Test complete'), findsNothing);
    // Neither leg produced a value — the stepper marks both as failed
    // (an X), not "done" (a check) and not silently blank.
    expect(find.byIcon(Icons.close_rounded), findsWidgets);
  });
}
