import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Dev-only frame timing log (build with --dart-define=WB_PERF_LOG=true):
/// once a second prints frame count, UI and raster time (average/95th
/// percentile/max) and
/// how many frames missed 16.7 ms — for measuring jank on a real phone
/// via `adb logcat -s flutter`. Off in every normal build.
const _enabled = bool.fromEnvironment('WB_PERF_LOG');

void startFrameLog() {
  if (!_enabled) return;
  final batch = <FrameTiming>[];
  var windowStart = DateTime.now();
  SchedulerBinding.instance.addTimingsCallback((timings) {
    batch.addAll(timings);
    final now = DateTime.now();
    if (now.difference(windowStart).inMilliseconds < 1000) return;
    windowStart = now;
    if (batch.isEmpty) return;
    double ms(Duration d) => d.inMicroseconds / 1000;
    final ui = batch.map((t) => ms(t.buildDuration)).toList();
    final raster = batch.map((t) => ms(t.rasterDuration)).toList();
    double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    double max(List<double> v) => v.reduce((a, b) => a > b ? a : b);
    double p95(List<double> v) {
      final s = [...v]..sort();
      return s[((s.length - 1) * 0.95).round()];
    }
    final slow = batch.where((t) => ms(t.totalSpan) > 16.7).length;
    debugPrint('[WB-PERF] frames=${batch.length} '
        'ui=${avg(ui).toStringAsFixed(1)}/${p95(ui).toStringAsFixed(1)}/${max(ui).toStringAsFixed(1)} '
        'raster=${avg(raster).toStringAsFixed(1)}/${p95(raster).toStringAsFixed(1)}/${max(raster).toStringAsFixed(1)} '
        'slow=$slow');
    batch.clear();
  });
}
