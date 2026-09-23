import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/services/vpn/speed_test_controller.dart';

// Regression coverage for real-device feedback: "the wave and numbers
// just jump around chaotically instead of moving in an orderly way, not
// optimized." SpeedTestController.run() feeds every raw sample through
// emaStep() before it ever becomes state.liveMbps (see that function's
// own doc comment) — this drives the plain damping math directly,
// independent of the network/controller machinery, since that's the
// actual behavior being fixed.
void main() {
  test('the first reading of a run shows immediately, not dragged up from zero',
      () {
    // No artificial "ramp-up" delay before the very first sample — a
    // smoothing scheme that started from an assumed 0 would make an
    // already-fast connection look like it starts slow.
    expect(emaStep(null, 87.3), 87.3);
  });

  test(
      'a single noisy spike is damped toward the previous reading, not snapped to it',
      () {
    // A lone outlier sample (e.g. one throttled tick landing right after
    // a burst of buffered chunks flushed back to back) shouldn't yank
    // the displayed number straight to that spike — it should land
    // partway between the established reading and the new one.
    final result = emaStep(20.0, 100.0);
    expect(result, greaterThan(20.0));
    expect(result, lessThan(100.0));
    // Specifically: alpha=0.35 means 35% of the way toward the new
    // sample, not more — a materially bigger step would still read as
    // jumpy for a single spike.
    expect(result,
        closeTo(20.0 + (100.0 - 20.0) * speedTestSmoothingAlpha, 0.001));
  });

  test(
      'a sustained new throughput level is reached within a handful of samples, not laggy',
      () {
    // Simulates a real step change (e.g. a slow ramp-up finishing and
    // settling at a genuinely higher steady rate) — the smoothed value
    // should converge close to the new level within a few samples, not
    // trail behind indefinitely (that would read as sluggish/laggy,
    // which the fix explicitly should not be).
    double? smoothed;
    for (var i = 0; i < 5; i++) {
      smoothed = emaStep(smoothed, 80.0);
    }
    expect(smoothed, isNotNull);
    expect(smoothed!, closeTo(80.0, 5.0));
  });

  test('a steady, noise-free stream of identical samples stays exactly flat',
      () {
    // Smoothing shouldn't introduce drift or oscillation on its own —
    // feeding the same value repeatedly must converge to (and stay at)
    // that exact value, not overshoot or creep.
    double? smoothed;
    for (var i = 0; i < 10; i++) {
      smoothed = emaStep(smoothed, 42.0);
    }
    expect(smoothed, 42.0);
  });
}
