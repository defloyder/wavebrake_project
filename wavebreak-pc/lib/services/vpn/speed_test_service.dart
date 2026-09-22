import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Result of one download+upload pass. Either side can be null if that
/// leg failed or was cancelled — the other still reports if it finished.
class SpeedTestResult {
  const SpeedTestResult({this.downloadMbps, this.uploadMbps});

  final double? downloadMbps;
  final double? uploadMbps;
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
class SpeedTestService {
  SpeedTestService({Dio? client}) : _dio = client ?? Dio();

  final Dio _dio;

  static const _downloadUrl = 'https://speed.cloudflare.com/__down';
  static const _uploadUrl = 'https://speed.cloudflare.com/__up';

  /// ~8MB download, ~4MB upload — enough for the initial TCP slow-start
  /// ramp to settle out on a reasonably fast connection without the test
  /// itself taking unreasonably long on a slow one (bounded below by
  /// [timeout] either way).
  static const _downloadBytes = 8 * 1000 * 1000;
  static const _uploadBytes = 4 * 1000 * 1000;

  /// Runs download then upload, each independently best-effort — a failed
  /// or timed-out leg leaves that side of [SpeedTestResult] null rather
  /// than aborting the whole test. [onPhase] reports which leg is running
  /// so the UI can label the spinner accordingly.
  Future<SpeedTestResult> run({
    void Function(SpeedTestPhase phase)? onPhase,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    onPhase?.call(SpeedTestPhase.download);
    final download = await _measureDownload(timeout);
    onPhase?.call(SpeedTestPhase.upload);
    final upload = await _measureUpload(timeout);
    return SpeedTestResult(downloadMbps: download, uploadMbps: upload);
  }

  Future<double?> _measureDownload(Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio.get<List<int>>(
        _downloadUrl,
        queryParameters: {'bytes': _downloadBytes},
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
      stopwatch.stop();
      final bytes = response.data?.length ?? 0;
      return _mbps(bytes, stopwatch.elapsed);
    } catch (_) {
      return null;
    }
  }

  Future<double?> _measureUpload(Duration timeout) async {
    final payload = _randomBytes(_uploadBytes);
    final stopwatch = Stopwatch()..start();
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
      );
      stopwatch.stop();
      return _mbps(payload.length, stopwatch.elapsed);
    } catch (_) {
      return null;
    }
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

enum SpeedTestPhase { download, upload }
