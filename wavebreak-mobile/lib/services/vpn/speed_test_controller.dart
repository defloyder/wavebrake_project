import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'speed_test_service.dart';

enum SpeedTestStatus { idle, testingDownload, testingUpload, done, failed }

class SpeedTestState {
  const SpeedTestState({
    this.status = SpeedTestStatus.idle,
    this.downloadMbps,
    this.uploadMbps,
  });

  final SpeedTestStatus status;
  final double? downloadMbps;
  final double? uploadMbps;

  bool get isRunning =>
      status == SpeedTestStatus.testingDownload || status == SpeedTestStatus.testingUpload;

  SpeedTestState copyWith({
    SpeedTestStatus? status,
    double? downloadMbps,
    double? uploadMbps,
  }) =>
      SpeedTestState(
        status: status ?? this.status,
        downloadMbps: downloadMbps ?? this.downloadMbps,
        uploadMbps: uploadMbps ?? this.uploadMbps,
      );
}

/// Drives [SpeedTestService] from the UI — works identically whether a
/// tunnel is up or not, see that class's own doc comment for why. One
/// run at a time; a second tap while [SpeedTestState.isRunning] is a
/// no-op rather than stacking overlapping probes.
final speedTestControllerProvider =
    NotifierProvider<SpeedTestController, SpeedTestState>(SpeedTestController.new);

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
