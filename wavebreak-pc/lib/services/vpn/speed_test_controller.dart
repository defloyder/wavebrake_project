import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  SpeedTestState build() => const SpeedTestState();

  Future<void> run() async {
    if (state.isRunning) return;
    state = const SpeedTestState(status: SpeedTestStatus.testingDownload);
    try {
      final result = await _service.run(
        onPhase: (phase) {
          state = state.copyWith(
            status: phase == SpeedTestPhase.download
                ? SpeedTestStatus.testingDownload
                : SpeedTestStatus.testingUpload,
            liveMbps: 0,
            progress: 0,
          );
        },
        onSample: (sample) {
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
      state = SpeedTestState(
        status: SpeedTestStatus.done,
        downloadMbps: result.downloadMbps,
        uploadMbps: result.uploadMbps,
      );
    } catch (_) {
      state = const SpeedTestState(status: SpeedTestStatus.failed);
    }
  }

  void reset() => state = const SpeedTestState();
}
