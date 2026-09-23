import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/services/vpn/speed_test_service.dart';

/// Feeds Dio a real, never-stalling stream of small chunks that keeps
/// "alive" indefinitely but very slowly — exactly the shape of
/// connection that used to defeat quickDownloadProbeMbps in production:
/// Dio's own receiveTimeout only fires on a STALL (a gap between
/// packets), and this stream never has one, so without a real
/// wall-clock cap the request would run until this stream is manually
/// stopped, not until any timeout Dio itself enforces.
class _SlowTrickleAdapter implements HttpClientAdapter {
  bool _cancelled = false;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    cancelFuture?.then((_) => _cancelled = true);
    final controller = StreamController<Uint8List>();
    Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_cancelled || controller.isClosed) {
        timer.cancel();
        if (!controller.isClosed) controller.close();
        return;
      }
      controller.add(Uint8List.fromList(List.filled(200, 1)));
    });
    return ResponseBody(
      controller.stream,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/octet-stream'],
      },
    );
  }
}

void main() {
  test(
    'a slow-but-steady (never-stalling) download is bounded by real wall-clock time',
    () async {
      final dio = Dio()..httpClientAdapter = _SlowTrickleAdapter();
      final service = SpeedTestService(client: dio);

      final stopwatch = Stopwatch()..start();
      final result = await service.quickDownloadProbeMbps(
        timeout: const Duration(milliseconds: 250),
      );
      stopwatch.stop();

      // The bug this guards against: with only Dio's stall-based
      // receiveTimeout, this stream (which never stalls — a chunk
      // arrives every 30ms) could run for a very long time. A real
      // wall-clock deadline bounds total elapsed to roughly one timeout
      // period (the first attempt has real partial bytes to report, so
      // no retry is needed) regardless of how "alive" the trickle looks.
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'a never-stalling but slow stream must still be bounded by '
            'real wall-clock time, not left running indefinitely',
      );
      // Partial bytes DID arrive before the deadline fired — that
      // partial throughput is real, useful signal ("this one's slow"),
      // not a bare failure.
      expect(result, isNotNull);
    },
  );
}
