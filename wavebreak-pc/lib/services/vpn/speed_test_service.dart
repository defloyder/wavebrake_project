import 'dart:async';
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
  /// [onPhase] fires once when each leg starts. [onLegDone] fires once
  /// per leg with that leg's OWN final average the moment it finishes —
  /// real-device bug this exists to fix: without it, a caller only finds
  /// out download's result once the ENTIRE run (download + upload) has
  /// finished, since [SpeedTestResult] itself isn't built until both
  /// legs are done — so a "download: – / upload: –" summary tile stayed
  /// blank through the whole upload leg despite download's own real
  /// number having been known for a while already.
  Future<SpeedTestResult> run({
    void Function(SpeedTestPhase phase)? onPhase,
    void Function(SpeedTestSample sample)? onSample,
    void Function(SpeedTestPhase phase, double? mbps)? onLegDone,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    onPhase?.call(SpeedTestPhase.download);
    final download = await _measureDownload(timeout, _downloadBytes, onSample);
    onLegDone?.call(SpeedTestPhase.download, download);
    onPhase?.call(SpeedTestPhase.upload);
    final upload = await _measureUpload(timeout, onSample);
    onLegDone?.call(SpeedTestPhase.upload, upload);
    return SpeedTestResult(downloadMbps: download, uploadMbps: upload);
  }

  /// A fast, download-only throughput reading — for
  /// ConnectionManager.connect()'s Auto-candidate selection factoring in
  /// "is it actually fast," not just "did it connect" (see that class's
  /// own doc comment). Deliberately much smaller/quicker than [run]'s
  /// full two-leg measurement: this runs once per candidate against a
  /// LIVE tunnel connection already holding up the rest of the app, and
  /// checking "at least 2-3 candidates" at the full ~28MB/20s-timeout
  /// scale would make Auto-connect itself feel broken from the delay.
  /// No live samples, no upload leg — just one number, fast.
  ///
  /// Real-device bug this default guards against: a slow candidate is
  /// exactly the one Auto-connect most wants to reject QUICKLY, not
  /// spend the longest time measuring — confirmed in production logs
  /// where a genuinely slow candidate's probe took over a minute on its
  /// own (a fixed ~1.5MB transfer at 0.2 Mbps is ~60s), during which the
  /// user's other apps cycled through every transport switch Auto-
  /// connect tried in turn. 3s here is deliberately short: see
  /// [_measureDownload]'s own comment for how this is actually enforced
  /// as real wall-clock time now, not just Dio's receiveTimeout (which
  /// only fires on a STALL, not on a slow-but-steady trickle that never
  /// stops sending SOME bytes — exactly what let the minute-long probe
  /// above happen without ever timing out on its own).
  Future<double?> quickDownloadProbeMbps({
    Duration timeout = const Duration(seconds: 3),
  }) {
    return _measureDownload(timeout, _quickProbeBytes, null);
  }

  // ~1.5MB — enough past TCP slow-start to give a meaningful (not just
  // "handshake completed instantly") reading without meaningfully
  // delaying an Auto-connect attempt.
  static const _quickProbeBytes = 1500 * 1000;

  // Real-device bug this class exists to guard against (confirmed via
  // production logs): Dio's receiveTimeout/sendTimeout only fire on a
  // STALL — a gap between two data packets exceeding the timeout — not
  // on the transfer simply taking a long time overall. A slow-but-
  // steady trickle that never stops sending SOME bytes (a genuinely slow
  // candidate, exactly the case a probe most needs to bail out of
  // quickly) can run for a minute or more without ever tripping that
  // timeout, because there's never a single gap long enough to count as
  // a stall. A [CancelToken] fired from a real wall-clock [Timer] is
  // what actually bounds total duration regardless of how the bytes are
  // arriving — cancelling on that timer, not waiting on receiveTimeout,
  // is what makes [timeout] mean what it says.
  //
  // A cancellation from a real timeout (as opposed to a genuine network
  // failure) still has SOME bytes to show for it via onReceiveProgress —
  // whatever throughput that partial transfer implies is itself useful
  // signal ("this one's slow, move on" — see quickDownloadProbeMbps's
  // own comment) rather than being thrown away as a bare failure.
  Future<double?> _measureDownload(
    Duration timeout,
    int bytes,
    void Function(SpeedTestSample sample)? onSample,
  ) async {
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      final stopwatch = Stopwatch()..start();
      final sampler = _ProgressSampler(SpeedTestPhase.download, onSample);
      final cancelToken = CancelToken();
      var lastBytes = 0;
      final deadline = Timer(timeout, () {
        cancelToken.cancel(_wallClockTimeoutReason);
      });
      try {
        final response = await _dio.get<List<int>>(
          _downloadUrl,
          queryParameters: {'bytes': bytes},
          cancelToken: cancelToken,
          options: Options(responseType: ResponseType.bytes),
          onReceiveProgress: (count, total) {
            lastBytes = count;
            sampler.onProgress(count, total);
          },
        );
        stopwatch.stop();
        final actualBytes = response.data?.length ?? 0;
        return _mbps(actualBytes, stopwatch.elapsed);
      } catch (error) {
        stopwatch.stop();
        if (_isWallClockTimeout(error) && lastBytes > 0) {
          return _mbps(lastBytes, stopwatch.elapsed);
        }
        // A one-off dropped connection/timeout mid-test shouldn't abandon
        // the whole measurement with nothing to show — retry once before
        // giving up. Not retried indefinitely: a connection that's
        // genuinely down should still resolve to a real "failed" state
        // (see SpeedTestController.run()) rather than hang retrying.
        if (attempt == _maxRetries) return null;
      } finally {
        deadline.cancel();
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
      final cancelToken = CancelToken();
      var lastBytes = 0;
      final deadline = Timer(timeout, () {
        cancelToken.cancel(_wallClockTimeoutReason);
      });
      try {
        await _dio.post<void>(
          _uploadUrl,
          data: Stream.fromIterable([payload]),
          cancelToken: cancelToken,
          options: Options(
            headers: {
              Headers.contentLengthHeader: payload.length,
              Headers.contentTypeHeader: 'application/octet-stream',
            },
          ),
          onSendProgress: (count, total) {
            lastBytes = count;
            sampler.onProgress(count, total);
          },
        );
        stopwatch.stop();
        return _mbps(payload.length, stopwatch.elapsed);
      } catch (error) {
        stopwatch.stop();
        if (_isWallClockTimeout(error) && lastBytes > 0) {
          return _mbps(lastBytes, stopwatch.elapsed);
        }
        if (attempt == _maxRetries) return null;
      } finally {
        deadline.cancel();
      }
    }
    return null;
  }

  static const _wallClockTimeoutReason = 'speed-test-wall-clock-timeout';

  bool _isWallClockTimeout(Object error) =>
      error is DioException &&
      error.type == DioExceptionType.cancel &&
      error.error == _wallClockTimeoutReason;

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
