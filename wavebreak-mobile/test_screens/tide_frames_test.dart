// ignore_for_file: depend_on_referenced_packages, invalid_use_of_visible_for_testing_member
// Speed-test bench: the real app on /speed-test, driven through a scripted
// run (idle → latency → download → upload → done) with made-up readings
// — only here, the app itself shows what SpeedTestController measures.
// Writes stills and GIF frames to test_screens/out/tide/<size>/.
//
//   flutter test test_screens/tide_frames_test.dart
//   WB_SIZES=412x915 WB_FRAMES=1 flutter test test_screens/tide_frames_test.dart
//   flutter test --dart-define=WAVEBREAK_TV=true test_screens/tide_frames_test.dart   (TV: 960x540)
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as gf;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavebreak/app/app.dart';
import 'package:wavebreak/app/router.dart';
import 'package:wavebreak/core/env/app_env.dart';
import 'package:wavebreak/core/storage/prefs_store.dart';
import 'package:wavebreak/core/storage/secure_store.dart';
import 'package:wavebreak/services/core_api/mock_backend.dart';
import 'package:wavebreak/services/vpn/speed_test_controller.dart';

import '../test/test_helpers.dart';
import 'screens_test.dart' show benchLocations;

class _Scripted extends SpeedTestController {
  @override
  SpeedTestState build() => const SpeedTestState();
  void set(SpeedTestState s) => state = s;
}

/// The scripted run, sampled at [t] seconds.
SpeedTestState _at(double t) {
  double ramp(double p, double top, double seed) =>
      top * (1 - math.exp(-p * 5)) + math.sin(p * 17 + seed) * top * 0.04;
  if (t < 0.8) return const SpeedTestState();
  if (t < 2.0) {
    return const SpeedTestState(status: SpeedTestStatus.testingLatency);
  }
  if (t < 6.0) {
    final p = (t - 2.0) / 4.0;
    return SpeedTestState(
        status: SpeedTestStatus.testingDownload,
        latencyMs: 31,
        liveMbps: ramp(p, 186, 0),
        progress: p);
  }
  if (t < 9.0) {
    final p = (t - 6.0) / 3.0;
    return SpeedTestState(
        status: SpeedTestStatus.testingUpload,
        latencyMs: 31,
        downloadMbps: 184,
        liveMbps: ramp(p, 47, 1),
        progress: p);
  }
  return const SpeedTestState(
      status: SpeedTestStatus.done,
      latencyMs: 31,
      downloadMbps: 184,
      uploadMbps: 46.8);
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('test_screens/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Inter_regular', ['Inter_regular.ttf']);
  await load('Inter_500', ['Inter_500.ttf']);
  await load('Inter_600', ['Inter_600.ttf']);
  await load('Inter_700', ['Inter_700.ttf']);
  await load('Michroma_regular', ['Michroma.ttf']);
  await load('serif', ['serif.ttf']);
  await load('Roboto', ['Inter_regular.ttf']);
  await load('FlutterTest', ['Inter_regular.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  setUpAll(() async {
    gf.httpClient = MockClient((_) => Completer<http.Response>().future);
    await _loadFonts();
  });

  final env = Platform.environment;
  final sizes = AppEnv.isTv
      ? const {'960x540': Size(960, 540)}
      : const {
          '320x640': Size(320, 640),
          '412x915': Size(412, 915),
          '820x1180': Size(820, 1180),
          '1280x800': Size(1280, 800),
        };
  final only = env['WB_SIZES']?.split(',');
  final frames = env['WB_FRAMES'] == '1';

  for (final entry in sizes.entries) {
    if (only != null && !only.contains(entry.key)) continue;
    final dir = 'test_screens/out/tide/${AppEnv.isTv ? 'tv-' : ''}${entry.key}';
    testWidgets(dir, (tester) async {
      await setUpTestEnvironment();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (call) async => ['wifi']);
      messenger.setMockStreamHandler(
          const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
          MockStreamHandler.inline(
              onListen: (_, sink) => sink.success(['wifi'])));
      messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async => {
                'appName': 'WAVEBREAK',
                'packageName': 'com.wavebreak.wavebreak',
                'version': '1.3.0',
                'buildNumber': '57',
              });
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exception is MissingPluginException) return;
        originalOnError?.call(details);
      };
      await PrefsStore.setBool(PrefsStore.onboardingChoiceMade, true);
      await PrefsStore.setString(PrefsStore.language, 'ru');
      await PrefsStore.setString(PrefsStore.lastLocationId, 'ist-h');
      await SecureStore.write(SecureStore.accessToken, 'mock-access');
      await SecureStore.write(SecureStore.refreshToken, 'mock-refresh');
      tester.view.physicalSize = entry.value * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final scripted = _Scripted();
      final key = GlobalKey();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...mockCoreOverrides(MockCoreBackend()..locations = benchLocations),
          speedTestControllerProvider.overrideWith(() => scripted),
        ],
        child: RepaintBoundary(key: key, child: const WavebreakApp()),
      ));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final container =
          ProviderScope.containerOf(tester.element(find.byType(WavebreakApp)));
      final GoRouter router = container.read(routerProvider);
      router.go('/speed-test');
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      Future<void> save(String name, double ratio) async {
        final boundary =
            tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: ratio);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$dir/$name.png')..createSync(recursive: true);
          file.writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
      }

      // Stills: one per state, after the surface settled.
      const stills = {
        '0-idle': 0.2,
        '1-latency': 1.5,
        '2-download': 5.0,
        '3-upload': 8.4,
        '4-done': 9.5,
      };
      for (final MapEntry(key: name, value: t) in stills.entries) {
        scripted.set(_at(t));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await save(name, 1);
      }

      // TV remote / keyboard: WB_KEYS=right,down,… then a still with focus.
      final keys = env['WB_KEYS']?.split(',') ?? const <String>[];
      if (keys.isNotEmpty) {
        scripted.set(const SpeedTestState());
        for (final k in keys) {
          await tester.sendKeyEvent(switch (k) {
            'left' => LogicalKeyboardKey.arrowLeft,
            'right' => LogicalKeyboardKey.arrowRight,
            'up' => LogicalKeyboardKey.arrowUp,
            'down' => LogicalKeyboardKey.arrowDown,
            'tab' => LogicalKeyboardKey.tab,
            _ => LogicalKeyboardKey.select,
          });
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        }
        // ignore: avoid_print
        print('focus: ${FocusManager.instance.primaryFocus}');
        await save('5-focus', 1);
      }

      // GIF frames: the whole run at 10 fps (state from the script, the
      // surface's own easing and ticker in between).
      if (frames) {
        scripted.set(const SpeedTestState());
        await tester.pump(const Duration(milliseconds: 600));
        for (var f = 0; f < 110; f++) {
          scripted.set(_at(f / 10));
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
          await save('f${f.toString().padLeft(3, '0')}',
              double.parse(env['WB_RATIO'] ?? '0.75'));
        }
      }

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      FlutterError.onError = originalOnError;
    });
  }
}
