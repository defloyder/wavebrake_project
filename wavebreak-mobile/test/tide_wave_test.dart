import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/features/speedtest/tide_wave.dart';

void main() {
  test('height follows the real speed on a log scale', () {
    expect(tideLevel(0), 0);
    expect(tideLevel(-3), 0);
    expect(tideLevel(500), closeTo(1, 1e-9));
    expect(tideLevel(5000), 1);
    // 10 Mbps already lifts the surface visibly, 100 more so.
    expect(tideLevel(10), greaterThan(0.3));
    expect(tideLevel(100), greaterThan(tideLevel(10)));
  });

  test('download flows forward in turquoise, upload back in red-pink', () {
    final down = TideTarget.of(TidePhase.download, 80);
    final up = TideTarget.of(TidePhase.upload, 80);
    expect(down.direction, 1);
    expect(down.color, tideDownload);
    expect(up.direction, -1);
    expect(up.color, tideUpload);
    // Same speed, same height and tempo — only direction and colour differ.
    expect(up.energy, down.energy);
    expect(up.flow, down.flow);
    // Faster is taller and quicker.
    final fast = TideTarget.of(TidePhase.download, 300);
    expect(fast.energy, greaterThan(down.energy));
    expect(fast.flow, greaterThan(down.flow));
    // Idle and latency ignore any speed (nothing measured yet).
    expect(TideTarget.of(TidePhase.idle, 999).energy,
        TideTarget.of(TidePhase.idle, 0).energy);
    expect(TideTarget.of(TidePhase.ping, 999).energy,
        TideTarget.of(TidePhase.ping, 0).energy);
  });

  Widget host(Widget child) => Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 400, height: 280, child: child),
      );

  testWidgets('reduced motion: a still surface, no ticker', (tester) async {
    await tester.pumpWidget(host(const TideWave(
        phase: TidePhase.download, mbps: 120, still: true)));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    // A new reading redraws once, still without starting a ticker.
    await tester.pumpWidget(host(
        const TideWave(phase: TidePhase.upload, mbps: 40, still: true)));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('animates while shown, stops with TickerMode and on dispose',
      (tester) async {
    await tester.pumpWidget(
        host(const TideWave(phase: TidePhase.download, mbps: 120)));
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.binding.hasScheduledFrame, isTrue);

    // An inactive tab (go_router's indexed stack mutes its tickers).
    await tester.pumpWidget(host(const TickerMode(
        enabled: false,
        child: TideWave(phase: TidePhase.download, mbps: 120))));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(host(const SizedBox()));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('pauses in the background', (tester) async {
    await tester.pumpWidget(
        host(const TideWave(phase: TidePhase.download, mbps: 120)));
    await tester.pump(const Duration(milliseconds: 40));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
  });
}
