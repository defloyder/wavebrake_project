import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_manager.dart';
import 'speed_test_service.dart';

enum SpeedTestStatus { idle, testingDownload, testingUpload, done, failed }

class SpeedTestState {
  const SpeedTestState({
    this.status = SpeedTestStatus.idle,
    this.downloadMbps,
    this.uploadMbps,
    this.liveMbps = 0,
    this.progress = 0,
  });

  final SpeedTestStatus status;
  final double? downloadMbps;
  final double? uploadMbps;

  /// The most recent live sample — what the gauge animates against while
  /// [isRunning]. Meaningless once [status] is `done`/`failed`/`idle`
  /// (the UI should read [downloadMbps]/[uploadMbps] instead at that
  /// point), but harmless to leave holding its last value.
  final double liveMbps;

  /// 0..1 through the current phase, for a progress ring/arc-fill
  /// distinct from the live-speed needle if the UI wants both.
  final double progress;

  bool get isRunning =>
      status == SpeedTestStatus.testingDownload ||
      status == SpeedTestStatus.testingUpload;

  SpeedTestState copyWith({
    SpeedTestStatus? status,
    double? downloadMbps,
    double? uploadMbps,
    double? liveMbps,
    double? progress,
  }) =>
      SpeedTestState(
        status: status ?? this.status,
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
    state = const SpeedTestState(status: SpeedTestStatus.testingDownload);
    try {
      final result = await _service.run(
        onPhase: (phase) {
          if (generation != _generation) return;
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
            liveMbps: sample.instantMbps,
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
    state = const SpeedTestState();
  }
}
