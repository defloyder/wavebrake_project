import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_manager.dart';
import 'connection_test_service.dart';
import 'speed_test_service.dart';

// Tuned to filter single-sample noise spikes without reading as
// sluggish: at ~200ms between samples (SpeedTestService's own
// throttle), 0.35 settles ~90% of the way to a real step change within
// 3-4 samples (well under a second) while still meaningfully damping a
// single outlier sample.
const speedTestSmoothingAlpha = 0.35;

/// A single-pole exponential moving average — see
/// [SpeedTestController]'s own doc comment on the real-device "numbers
/// jump around chaotically" bug this exists to fix. A top-level function
/// (not private to the controller, and not annotated
/// @visibleForTesting — this app doesn't otherwise depend on
/// package:meta, and one annotation isn't worth adding it) specifically
/// so this damping behavior is directly unit-testable without needing
/// to drive a whole SpeedTestService network probe end to end — see
/// test/speed_test_smoothing_test.dart.
///
/// [previous] null means "no reading yet" — returns [raw] unchanged so
/// the very first sample of a run shows immediately rather than being
/// artificially dragged up from zero.
double emaStep(double? previous, double raw,
        {double alpha = speedTestSmoothingAlpha}) =>
    previous == null ? raw : previous + (raw - previous) * alpha;

enum SpeedTestStatus {
  idle,
  testingLatency,
  testingDownload,
  testingUpload,
  done,
  failed,
}

class SpeedTestState {
  const SpeedTestState({
    this.status = SpeedTestStatus.idle,
    this.latencyMs,
    this.downloadMbps,
    this.uploadMbps,
    this.liveMbps = 0,
    this.progress = 0,
  });

  final SpeedTestStatus status;

  /// A real TCP-connect-timing reading against the active location — see
  /// connection_test_service.dart. Measured as the first step of [run],
  /// mirroring how established speed-test tools (Ookla, Fast.com,
  /// Cloudflare's own) always show latency before throughput: it's the
  /// fastest signal to get back, so the test visibly starts doing
  /// something within a moment of tapping Start rather than sitting on a
  /// blank gauge for however long the first download probe takes to ramp
  /// up. Null while pending/if it failed — a failed ping doesn't fail the
  /// whole test, download/upload still run.
  final int? latencyMs;
  final double? downloadMbps;
  final double? uploadMbps;

  /// The most recent live sample — what the wave meter animates against
  /// while [isRunning]. Meaningless once [status] is
  /// `done`/`failed`/`idle` (the UI should read
  /// [downloadMbps]/[uploadMbps] instead at that point), but harmless to
  /// leave holding its last value.
  final double liveMbps;

  /// 0..1 through the current phase, for a determinate progress
  /// indicator distinct from the live-speed reading.
  final double progress;

  bool get isRunning =>
      status == SpeedTestStatus.testingLatency ||
      status == SpeedTestStatus.testingDownload ||
      status == SpeedTestStatus.testingUpload;

  SpeedTestState copyWith({
    SpeedTestStatus? status,
    int? latencyMs,
    double? downloadMbps,
    double? uploadMbps,
    double? liveMbps,
    double? progress,
  }) =>
      SpeedTestState(
        status: status ?? this.status,
        latencyMs: latencyMs ?? this.latencyMs,
        downloadMbps: downloadMbps ?? this.downloadMbps,
        uploadMbps: uploadMbps ?? this.uploadMbps,
        liveMbps: liveMbps ?? this.liveMbps,
        progress: progress ?? this.progress,
      );
}

/// Drives [SpeedTestService] from the UI — works identically whether a
/// tunnel is up or not, see that class's own doc comment for why. One
/// run at a time; a second tap while [SpeedTestState.isRunning] is a
/// no-op rather than stacking overlapping probes.
final speedTestControllerProvider =
    NotifierProvider<SpeedTestController, SpeedTestState>(
        SpeedTestController.new);

class SpeedTestController extends Notifier<SpeedTestState> {
  final _service = SpeedTestService();

  // Real-device bug this exists to fix: switching to a different
  // location/connection and running the test again showed the PREVIOUS
  // connection's numbers instead of starting fresh. Two separate causes,
  // both fixed here:
  //  1. This provider is NOT autoDispose (deliberately — Home's own
  //     speed-test entry point shows the last result at a glance even
  //     when the speed-test page isn't mounted), so nothing ever reset
  //     its state just from navigating away and back.
  //  2. Even with a reset on location change, a `run()` already in
  //     flight when the connection switches (mid-test, via a real
  //     network handover or the app's own Auto-candidate fallback) has
  //     no way to know its result is now stale — its callbacks would
  //     otherwise land after the reset and silently overwrite the fresh
  //     state with the abandoned run's late-arriving numbers. Every
  //     mutation below checks [_generation] against the value captured
  //     when that particular run/reset started, exactly the same
  //     stale-callback guard connection_manager.dart's own
  //     `_connectGeneration` uses for the identical class of race.
  int _generation = 0;
  String? _lastLocationId;

  // Real-device feedback this exists to fix: "the wave and numbers just
  // jump around chaotically instead of moving in an orderly way." A raw
  // per-sample instantaneous rate genuinely IS noisy — a throttled
  // sample can land right after a burst of buffered chunks flushed back
  // to back, or right before a brief stall, and driving the display
  // straight off that raw number makes ordinary transfer variance read
  // as the UI itself being broken. An exponential moving average here —
  // smoothing the number BEFORE it ever becomes state.liveMbps, not just
  // in the widget that happens to render it — means every consumer of
  // this state (the wave meter's fill AND its own number display, which
  // used to read the raw value straight from the outer screen,
  // bypassing whatever smoothing lived only inside the meter widget)
  // sees the same already-smoothed number. WaveMeter's own per-frame
  // interpolation on top of this handles animating BETWEEN these
  // updates smoothly; this is what keeps the updates themselves from
  // being noisy in the first place.
  double? _smoothedMbps;

  double _smooth(double raw) {
    _smoothedMbps = emaStep(_smoothedMbps, raw);
    return _smoothedMbps!;
  }

  @override
  SpeedTestState build() {
    final locationId =
        ref.watch(connectionManagerProvider.select((s) => s.location.id));
    final isRealChange =
        _lastLocationId != null && _lastLocationId != locationId;
    _lastLocationId = locationId;
    if (isRealChange) {
      // Bumping the generation here (not just returning fresh state) is
      // what makes an in-flight run's late callbacks from the OLD
      // connection into no-ops instead of silently resurrecting stale
      // numbers a moment after this reset.
      _generation++;
    }
    return const SpeedTestState();
  }

  Future<void> run() async {
    if (state.isRunning) return;
    final generation = ++_generation;
    _smoothedMbps = null;
    state = const SpeedTestState(status: SpeedTestStatus.testingLatency);
    // A real TCP-connect-timing probe against whatever location is
    // currently active — same mechanism the location list's own ping
    // uses (ConnectionTestService), not a fabricated number. A failed
    // reading (custom server with no resolvable target, Hysteria2's
    // honest-null, a timeout) leaves latencyMs null rather than aborting
    // the whole test — download/upload below don't depend on it.
    try {
      final location = ref.read(connectionManagerProvider).location;
      final latency =
          await const ConnectionTestService().testLocation(location);
      if (generation != _generation) return;
      state = state.copyWith(latencyMs: latency);
    } catch (_) {
      // Best-effort — see the comment above.
    }
    if (generation != _generation) return;
    state = state.copyWith(status: SpeedTestStatus.testingDownload);
    try {
      final result = await _service.run(
        onPhase: (phase) {
          if (generation != _generation) return;
          // A fresh phase starts from a real zero, not wherever the
          // previous leg's smoothed value happened to settle — carrying
          // download's smoothing state into upload would drag upload's
          // first real readings toward download's old number instead of
          // rising cleanly from zero.
          _smoothedMbps = null;
          state = state.copyWith(
            status: phase == SpeedTestPhase.download
                ? SpeedTestStatus.testingDownload
                : SpeedTestStatus.testingUpload,
            liveMbps: 0,
            progress: 0,
          );
        },
        onSample: (sample) {
          if (generation != _generation) return;
          // Guards against a stray late callback from a phase the UI has
          // already moved on from (e.g. the download request's own
          // cleanup firing one more progress tick after onPhase already
          // switched to upload).
          final expectedStatus = sample.phase == SpeedTestPhase.download
              ? SpeedTestStatus.testingDownload
              : SpeedTestStatus.testingUpload;
          if (state.status != expectedStatus) return;
          state = state.copyWith(
            liveMbps: _smooth(sample.instantMbps),
            progress: sample.progress,
          );
        },
      );
      // The run this result belongs to has already been superseded by a
      // newer run or a connection-change reset — whatever state exists
      // now is more current than this result, so don't touch it.
      if (generation != _generation) return;
      if (result.downloadMbps == null && result.uploadMbps == null) {
        // Both legs failed (already retried once each inside
        // SpeedTestService — see its own doc comment) — this is a real
        // failure, not a "done" test with nothing to show. Reporting
        // `done` here is exactly the "no final result shown" bug: the
        // button would read "Test again" and the gauge would just sit at
        // zero with no indication anything went wrong.
        state = const SpeedTestState(status: SpeedTestStatus.failed);
        return;
      }
      state = SpeedTestState(
        status: SpeedTestStatus.done,
        downloadMbps: result.downloadMbps,
        uploadMbps: result.uploadMbps,
      );
    } catch (_) {
      if (generation != _generation) return;
      state = const SpeedTestState(status: SpeedTestStatus.failed);
    }
  }

  void reset() {
    _generation++;
    _smoothedMbps = null;
    state = const SpeedTestState();
  }
}
