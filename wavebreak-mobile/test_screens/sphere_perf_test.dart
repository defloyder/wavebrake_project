// ignore_for_file: depend_on_referenced_packages
// Sphere painter bench: time to record one frame of the connect core
// (the UI-thread part of P5) and its pixels, to check that an
// optimization doesn't change the picture.
//
//   flutter test test_screens/sphere_perf_test.dart
//
// Writes test_screens/out/sphere_<case>.rgba; a file named
// sphere_<case>.ref.rgba next to it (a copy of an earlier run) is compared
// pixel by pixel. Times are from the test VM (JIT), not a phone — compare
// before/after on the same machine only. Shaders don't run here, the
// sphere body is its plain stand-in (the orbits, glows and glass are real).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/features/immersive/effects_quality.dart';
import 'package:wavebreak/features/immersive/living_core.dart';
import 'package:wavebreak/features/immersive/sphere_assets.dart';
import 'package:wavebreak/features/shared/wave_params.dart';
import 'package:wavebreak/services/vpn/connection_manager.dart';

import '../test/test_helpers.dart';

class _Case {
  const _Case(this.name, this.status, {this.tint, this.economy = false});
  final String name;
  final ConnectionStatus status;
  final Color? tint;
  final bool economy;
}

const _cases = [
  _Case('idle', ConnectionStatus.idle),
  _Case('connected-blue', ConnectionStatus.connected,
      tint: Color(0xFF2F6BFF)),
  _Case('economy-green', ConnectionStatus.connected,
      tint: Color(0xFF1FB45A), economy: true),
];

const _size = Size(412, 320);

void main() {
  setUpAll(() async {
    await setUpTestEnvironment();
    SphereAssets.broken = true; // the stand-in, deterministic
  });

  for (final k in _cases) {
    testWidgets('sphere ${k.name}', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          effectsEconomyProvider.overrideWithValue(k.economy),
          appWaveParamsProvider.overrideWithValue(WaveParams(tint: k.tint)),
        ],
        child: MaterialApp(
          home: Center(
            child: SizedBox.fromSize(
              size: _size,
              child: LivingCore(
                status: k.status,
                enabled: true,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 1)); // tint tween settles
      final painter = tester
          .widget<CustomPaint>(find.descendant(
              of: find.byType(LivingCore), matching: find.byType(CustomPaint)))
          .painter!;

      ui.Picture record() {
        final rec = ui.PictureRecorder();
        painter.paint(Canvas(rec), _size);
        return rec.endRecording();
      }

      for (var i = 0; i < 50; i++) {
        record().dispose(); // warm-up (JIT)
      }
      const n = 400;
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        record().dispose();
      }
      sw.stop();
      final us = sw.elapsedMicroseconds / n;

      final picture = record();
      final bytes = await tester.runAsync(() async {
        final img = await picture.toImage(
            _size.width.toInt(), _size.height.toInt());
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        return data!.buffer.asUint8List();
      });
      picture.dispose();

      final out = Directory('test_screens/out')..createSync(recursive: true);
      File('${out.path}/sphere_${k.name}.rgba').writeAsBytesSync(bytes!);
      final ref = File('${out.path}/sphere_${k.name}.ref.rgba');
      var cmp = 'no reference';
      if (ref.existsSync()) {
        final a = ref.readAsBytesSync();
        cmp = _compare(a, bytes);
        await _png(tester, a, '${out.path}/sphere_${k.name}.ref.png');
      }
      await _png(tester, bytes, '${out.path}/sphere_${k.name}.png');
      // ignore: avoid_print
      print('[SPHERE] ${k.name}: record ${us.toStringAsFixed(1)} µs/frame; '
          'pixels vs ref: $cmp');
    });
  }
}

Future<void> _png(WidgetTester tester, Uint8List rgba, String path) =>
    tester.runAsync(() async {
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(rgba, _size.width.toInt(),
          _size.height.toInt(), ui.PixelFormat.rgba8888, done.complete);
      final img = await done.future;
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      File(path).writeAsBytesSync(png!.buffer.asUint8List());
    });

String _compare(Uint8List a, Uint8List b) {
  if (a.length != b.length) return 'size differs';
  var maxDiff = 0, over8 = 0;
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    sum += d;
    if (d > maxDiff) maxDiff = d;
    if (d > 8) over8++;
  }
  return 'max $maxDiff, mean ${(sum / a.length).toStringAsFixed(3)}, '
      '>8: $over8 of ${a.length} channels';
}
