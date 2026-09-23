import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/features/speedtest/speed_test_screen.dart';
import 'package:wavebreak/services/vpn/speed_test_controller.dart';
import 'package:wavebreak/services/vpn/speed_test_service.dart';

import 'test_helpers.dart';

/// Real feedback this file exists to reproduce and prove fixed: "until I
/// turn off the VPN and enter the page again, only then does it show me
/// the measurements" — completing a speed test while staying on the
/// page and not touching the connection left the final numbers stuck
/// un-rendered, even though the underlying state genuinely did reach
/// `done` (reopening the page proved that). Every earlier widget test
/// for this screen drove a FIXED SpeedTestState through the provider
/// (see speed_test_screen_test.dart) — none of them ever exercised a
/// real, in-flight `run()` completing while the SAME widget instance
/// stayed mounted the whole time, which is exactly the gap the real bug
/// lived in. This test does the real thing: pump the screen once, run a
/// REAL SpeedTestController.run() (against a fake-but-real Dio
/// transport, not a hand-set state), advance time, and assert the
/// SAME still-mounted widget ends up showing the completed result —
/// no remount, no reconnect, nothing touched but time passing.
class _InstantAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Drain the request stream (the upload leg sends one) so nothing is
    // left half-consumed, then answer with a small fixed body — real
    // network calls entirely, just against an in-memory transport
    // instead of the real internet. The upload leg gets a deliberate
    // small delay: instant-everything made every leg resolve inside a
    // single pumped frame, so the test could never actually observe an
    // intermediate moment ("upload in flight, download already has its
    // result") — exactly the moment the real bug this test guards
    // against was about. A delay here, not on download, guarantees the
    // pumped loop below gets at least one frame squarely inside that
    // window.
    if (options.method == 'POST') {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    final body = Uint8List(2000);
    return ResponseBody.fromBytes(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/octet-stream'],
      },
    );
  }
}

void main() {
  setUp(setUpTestEnvironment);

  testWidgets(
    'a completed speed test renders its final result on the same still-mounted screen, without a reconnect or remount',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeService = SpeedTestService(
          client: Dio()..httpClientAdapter = _InstantAdapter());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            speedTestControllerProvider
                .overrideWith(() => SpeedTestController(service: fakeService)),
          ],
          child: const MaterialApp(home: SpeedTestScreen()),
        ),
      );
      await tester.pump();

      // The actual real user interaction — tapping the on-screen Start
      // button — not a programmatic notifier.run() call, in case the
      // button's own onPressed wiring (a bare `notifier.run` tear-off,
      // not `() => notifier.run()`) behaves differently under real
      // widget event dispatch than a direct call does.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SpeedTestScreen)),
      );
      await tester.tap(find.text('Start test'));
      await tester.pump();

      // Advance real async work (the latency probe, then download, then
      // upload) plus enough frames for the wave meter's own repeating
      // animation controller in between — bounded, not pumpAndSettle
      // (that never returns while an animation keeps repeating).
      var sawDownloadResultDuringUpload = false;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final current = container.read(speedTestControllerProvider);
        // Regression coverage for a real-device bug: the download
        // summary tile stayed on "–" through the whole upload leg even
        // though download's own result had been known since the moment
        // it finished. If this run's timing ever lands a pumped frame
        // while upload is in flight, download's result must already be
        // visible then — not only once the entire run is done.
        if (current.status == SpeedTestStatus.testingUpload &&
            current.downloadMbps != null) {
          sawDownloadResultDuringUpload = true;
        }
        if (current.status == SpeedTestStatus.done ||
            current.status == SpeedTestStatus.failed) {
          break;
        }
      }

      final finalState = container.read(speedTestControllerProvider);
      expect(
        finalState.status,
        SpeedTestStatus.done,
        reason: 'the run should have completed successfully against the '
            'fake transport within the pumped time budget',
      );

      // One more settle pump so the just-landed state has a chance to
      // paint, then check the SAME widget (never rebuilt/remounted) is
      // actually showing it.
      await tester.pump();
      expect(
        find.text('Test complete'),
        findsOneWidget,
        reason: 'the still-mounted screen must reflect the completed '
            'result on its own — the real bug was that it silently '
            'didn\'t, and only reopening the page (a fresh widget mount) '
            'ever showed it',
      );
      expect(finalState.downloadMbps, isNotNull);
      expect(finalState.uploadMbps, isNotNull);
      expect(
        sawDownloadResultDuringUpload,
        isTrue,
        reason: 'download\'s result must be visible while upload is still '
            'running, not only once the whole test is done',
      );
    },
  );
}
