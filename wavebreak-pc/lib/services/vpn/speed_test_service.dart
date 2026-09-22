import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Result of one download+upload pass. Either side can be null if that
/// leg failed or was cancelled — the other still reports if it finished.
/// These are the pass's overall averages (total bytes / total time) —
/// [SpeedTestService.run]'s `onSample` callback is the live, moment-to-
/// moment reading the gauge animates against.
class SpeedTestResult {
  const SpeedTestResult({this.downloadMbps, this.uploadMbps});

  final double? downloadMbps;
  final double? uploadMbps;
}

enum SpeedTestPhase { download, upload }

/// A live throughput reading during a transfer — what's fed to the gauge
/// while a test is in progress. [instantMbps] is the rate since the
/// previous sample, not the running average, so the gauge visibly
/// responds to a connection speeding up or stalling mid-test instead of
/// slowly converging on one number.
class SpeedTestSample {
  const SpeedTestSample({
    required this.phase,
    required this.instantMbps,
    required this.progress,
  });

  final SpeedTestPhase phase;
  final double instantMbps;

  /// 0..1 through the current phase's transfer.
  final double progress;
}

/// Plain HTTP download/upload throughput probe — no native code, no VPN
/// awareness needed. Whichever interface this process's sockets currently
/// go through (the real network directly, or the app's own VPN tunnel
/// when one is up — Android/Windows both capture this app's own traffic
/// into an active tunnel the same as any other app's) is exactly what
/// gets measured, which is the point: run it while connected to see the
/// tunnel's effective throughput, or while disconnected to see the raw
/// connection.
///
/// Uses Cloudflare's public speed-test endpoints (no API key, no
/// WAVEBREAK-operated backend needed) — the same `speed.cloudflare.com`
/// service the well-known browser speed test at speed.cloudflare.com
/// itself calls.
///
/// Live samples come from Dio's own onReceiveProgress/onSendProgress
/// callbacks — no extra dependency, no manual chunking needed. Those
/// callbacks fire far more often than a gauge needs redrawing (every
/// packet/buffer flush), so samples are throttled to
/// [_minSampleInterval] here rather than passing every callback straight
/// through to the UI.
class SpeedTestService {
  SpeedTestService({Dio? client}) : _dio = client ?? Dio();

  final Dio _dio;

  static const _downloadUrl = 'https://speed.cloudflare.com/__down';
  static const _uploadUrl = 'https://speed.cloudflare.com/__up';

  /// ~20MB download, ~8MB upload — enough for the initial TCP slow-start
  /// ramp to settle out on a reasonably fast connection, and enough
  /// duration to actually show a handful of live samples rather than the
  /// whole transfer completing between two callback ticks.
  static const _downloadBytes = 20 * 1000 * 1000;
  static const _uploadBytes = 8 * 1000 * 1000;

  // A few times a second is plenty for a gauge animation to read as
  // live/smooth — sampling faster than the UI can meaningfully
  // distinguish would just be wasted work and jumpier-looking numbers
  // from smaller, noisier deltas.
  static const _minSampleInterval = Duration(milliseconds: 200);

  // One retry per leg — a transient drop/timeout mid-test (a network
  // blip, or the VPN engine's own reconnect kicking in) used to abandon
  // the whole measurement with nothing to show at all. Not more than
  // one: a connection that's genuinely down should still resolve to a
  // real failure promptly rather than retrying indefinitely.
  static const _maxRetries = 1;

  /// Runs download then upload, each independently best-effort — a failed
  /// or timed-out leg leaves that side of [SpeedTestResult] null rather
  /// than aborting the whole test. [onSample] fires periodically
  /// (throttled, see class doc) during each leg with a live reading;
  /// [onPhase] fires once when each leg starts.
  Future<SpeedTestResult> run({
    void Function(SpeedTestPhase phase)? onPhase,
    void Function(SpeedTestSample sample)? onSample,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    onPhase?.call(SpeedTestPhase.download);
    final download = await _measureDownload(timeout, onSample);
    onPhase?.call(SpeedTestPhase.upload);
    final upload = await _measureUpload(timeout, onSample);
    return SpeedTestResult(downloadMbps: download, uploadMbps: upload);
  }

  Future<double?> _measureDownload(
    Duration timeout,
    void Function(SpeedTestSample sample)? onSample,
  ) async {
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      final stopwatch = Stopwatch()..start();
      final sampler = _ProgressSampler(SpeedTestPhase.download, onSample);
      try {
        final response = await _dio.get<List<int>>(
          _downloadUrl,
          queryParameters: {'bytes': _downloadBytes},
          options: Options(
            responseType: ResponseType.bytes,
            sendTimeout: timeout,
            receiveTimeout: timeout,
          ),
          onReceiveProgress: sampler.onProgress,
        );
        stopwatch.stop();
        final bytes = response.data?.length ?? 0;
        return _mbps(bytes, stopwatch.elapsed);
      } catch (_) {
        // A one-off dropped connection/timeout mid-test shouldn't abandon
        // the whole measurement with nothing to show — retry once before
        // giving up. Not retried indefinitely: a connection that's
        // genuinely down should still resolve to a real "failed" state
        // (see SpeedTestController.run()) rather than hang retrying.
        if (attempt == _maxRetries) return null;
      }
    }
    return null;
  }

  Future<double?> _measureUpload(
    Duration timeout,
    void Function(SpeedTestSample sample)? onSample,
  ) async {
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      final payload = _randomBytes(_uploadBytes);
      final stopwatch = Stopwatch()..start();
      final sampler = _ProgressSampler(SpeedTestPhase.upload, onSample);
      try {
        await _dio.post<void>(
          _uploadUrl,
          data: Stream.fromIterable([payload]),
          options: Options(
            headers: {
              Headers.contentLengthHeader: payload.length,
              Headers.contentTypeHeader: 'application/octet-stream',
            },
            sendTimeout: timeout,
            receiveTimeout: timeout,
          ),
          onSendProgress: sampler.onProgress,
        );
        stopwatch.stop();
        return _mbps(payload.length, stopwatch.elapsed);
      } catch (_) {
        if (attempt == _maxRetries) return null;
      }
    }
    return null;
  }

  double? _mbps(int bytes, Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1e6;
    if (bytes <= 0 || seconds <= 0) return null;
    // bytes -> bits -> megabits/sec.
    return (bytes * 8) / seconds / 1e6;
  }

  Uint8List _randomBytes(int length) {
    final random = Random();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}

/// Converts Dio's cumulative (count, total) progress callback into
/// throttled, instantaneous-rate [SpeedTestSample]s.
class _ProgressSampler {
  _ProgressSampler(this.phase, this.onSample);

  final SpeedTestPhase phase;
  final void Function(SpeedTestSample sample)? onSample;

  // Below this, a bytes/seconds division is dominated by callback jitter
  // rather than anything real — two Dio progress ticks can fire a handful
  // of microseconds apart when several buffered chunks flush back to
  // back, and dividing real bytes by a near-zero elapsed time produces an
  // enormous, meaningless rate (confirmed real-device bug: the gauge
  // occasionally showed something like "349349" Mbps). 15ms is well
  // below anything a real network round trip takes, so it only ever
  // filters out these same-tick artifacts, never a genuine fast sample.
  static const _minMeaningfulInterval = Duration(milliseconds: 15);

  final Stopwatch _stopwatch = Stopwatch()..start();
  int _lastBytes = 0;
  Duration _lastElapsed = Duration.zero;
  double _lastInstantMbps = 0;

  void onProgress(int count, int total) {
    if (onSample == null || total <= 0) return;
    final elapsed = _stopwatch.elapsed;
    final sinceLastSample = elapsed - _lastElapsed;
    final isFinal = count >= total;
    // Always let the final callback through even if it arrives before the
    // throttle window — otherwise a fast transfer could finish between
    // two throttled samples and the gauge would visibly freeze short of
    // 100% for the rest of that phase.
    if (sinceLastSample < SpeedTestService._minSampleInterval && !isFinal) {
      return;
    }
    // The final callback still needs to report progress: 1.0, but if it
    // arrived too soon after the last real sample to compute a sane rate
    // from, reuse the last good instantMbps instead of dividing by a
    // near-zero elapsed time — a repeated-but-plausible number reads as
    // "the test just finished right where it was," not a display glitch.
    if (sinceLastSample >= _minMeaningfulInterval) {
      final deltaBytes = count - _lastBytes;
      final deltaSeconds = sinceLastSample.inMicroseconds / 1e6;
      final instantMbps = (deltaBytes * 8) / deltaSeconds / 1e6;
      _lastInstantMbps = instantMbps < 0 ? 0 : instantMbps;
      _lastBytes = count;
      _lastElapsed = elapsed;
    }
    onSample!(SpeedTestSample(
      phase: phase,
      instantMbps: _lastInstantMbps,
      progress: count / total,
    ));
  }
}
