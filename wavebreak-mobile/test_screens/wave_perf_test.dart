// ignore_for_file: depend_on_referenced_packages
// Wave field bench: time to record one frame of the background waves
// (UI-thread cost), test VM only — compare before/after on one machine.
//
//   flutter test test_screens/wave_perf_test.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/features/immersive/effects_quality.dart';
import 'package:wavebreak/features/immersive/wave_field.dart';

import '../test/test_helpers.dart';

void main() {
  setUpAll(setUpTestEnvironment);

  for (final layers in [16, 26]) {
    testWidgets('waves $layers layers', (tester) async {
      const size = Size(412, 915);
      await tester.pumpWidget(ProviderScope(
        overrides: [effectsEconomyProvider.overrideWithValue(false)],
        child: MaterialApp(
          home: SizedBox.fromSize(
            size: size,
            child: WaveField(layers: layers, tint: const Color(0xFFE30A17)),
          ),
        ),
      ));
      final painter = tester
          .widget<CustomPaint>(find.descendant(
              of: find.byType(WaveField), matching: find.byType(CustomPaint)))
          .painter!;
      void record() {
        final rec = ui.PictureRecorder();
        painter.paint(Canvas(rec), size);
        rec.endRecording().dispose();
      }

      for (var i = 0; i < 50; i++) {
        record();
      }
      const n = 300;
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        record();
      }
      // ignore: avoid_print
      print('[WAVES] $layers layers: ${(sw.elapsedMicroseconds / n).toStringAsFixed(1)} µs/frame');
    });
  }
}
