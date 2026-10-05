// Screenshot bench: renders the real app (mock Core, signed in) at several
// phone/tablet sizes and text scales and writes PNGs to test_screens/out/.
//
//   flutter test test_screens --update-goldens
//
// Not part of the normal `flutter test` run (lives outside test/). Fonts
// are the real ones (Inter via google_fonts' family names, Noto Serif for
// "serif") so text measures like on a phone. Fragment shaders don't run
// under flutter_tester: the sphere shows its plain stand-in here.
//
// Filter: WB_SHOTS=home,settings  WB_SIZES=360x640  WB_LANG=ru
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:wavebreak/core/i18n/language_controller.dart';
import 'package:wavebreak/core/storage/prefs_store.dart';
import 'package:wavebreak/core/storage/secure_store.dart';

import '../test/test_helpers.dart';

class Shot {
  const Shot(this.name, this.path, {this.signedIn = true, this.firstRun = false});
  final String name;
  final String path;
  final bool signedIn;

  /// Guest-or-account not chosen yet (the welcome screen).
  final bool firstRun;
}

const shots = [
  Shot('welcome', '/welcome', signedIn: false, firstRun: true),
  Shot('login', '/login', signedIn: false),
  Shot('email-code', '/email-code', signedIn: false),
  Shot('home', '/home'),
  Shot('servers', '/locations'),
  Shot('test', '/speed-test'),
  Shot('metrics', '/metrics'),
  Shot('settings', '/settings'),
  Shot('account', '/settings/account'),
  Shot('connection', '/settings/connection'),
  Shot('security', '/settings/security'),
  Shot('notifications', '/settings/notifications'),
  Shot('personalization', '/settings/personalization'),
  Shot('support', '/settings/support'),
  Shot('about', '/settings/about'),
  Shot('updates', '/settings/updates'),
  Shot('subscription', '/subscription'),
];

const sizes = <String, Size>{
  '320x568': Size(320, 568),
  '360x640': Size(360, 640),
  '412x915': Size(412, 915),
  '800x1280': Size(800, 1280),
  '1280x800': Size(1280, 800),
};

List<String>? _env(String k) {
  final v = Platform.environment[k];
  return v == null || v.isEmpty ? null : v.split(',');
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
  // flutter_tester's default family (box glyphs): text with no family set
  // (painters, some labels) gets Inter instead, like Roboto on a phone.
  await load('FlutterTest', ['Inter_regular.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  setUpAll(() async {
    // google_fonts would download Inter and fail without a network: a
    // client that never answers leaves the fonts loaded below in place.
    gf.httpClient = MockClient((_) => Completer<http.Response>().future);
    await _loadFonts();
  });

  final onlyShots = _env('WB_SHOTS');
  final onlySizes = _env('WB_SIZES');
  final langs = _env('WB_LANG') ?? ['ru'];
  final scales = (_env('WB_SCALES') ?? ['1.0', '1.3']).map(double.parse);

  for (final lang in langs) {
    for (final entry in sizes.entries) {
      if (onlySizes != null && !onlySizes.contains(entry.key)) continue;
      for (final scale in scales) {
        // Tablets only at 1.0 (the small-screen work is about phones).
        if (entry.value.shortestSide >= 600 && scale != 1.0) continue;
        for (final shot in shots) {
          if (onlyShots != null && !onlyShots.contains(shot.name)) continue;
          final file = 'out/$lang/${entry.key}@${scale}x/${shot.name}.png';
          testWidgets(file, (tester) async {
            await setUpTestEnvironment();
            final messenger =
                TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
            // Online (no offline banner on the shots).
            messenger.setMockMethodCallHandler(
                const MethodChannel('dev.fluttercommunity.plus/connectivity'),
                (call) async => ['wifi']);
            messenger.setMockStreamHandler(
                const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
                MockStreamHandler.inline(onListen: (_, sink) => sink.success(['wifi'])));
            // Platform plugins don't exist under flutter_tester: ignore those.
            final originalOnError = FlutterError.onError;
            FlutterError.onError = (details) {
              if (details.exception is MissingPluginException) return;
              originalOnError?.call(details);
            };
            await PrefsStore.setBool(
                PrefsStore.onboardingChoiceMade, !shot.firstRun);
            await PrefsStore.setString(PrefsStore.language, lang);
            if (shot.signedIn) {
              await SecureStore.write(SecureStore.accessToken, 'mock-access');
              await SecureStore.write(SecureStore.refreshToken, 'mock-refresh');
            }
            tester.view.physicalSize = entry.value * 2;
            tester.view.devicePixelRatio = 2;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

            await tester.pumpWidget(
              ProviderScope(
                overrides: mockCoreOverrides(),
                child: const WavebreakApp(),
              ),
            );
            for (var i = 0; i < 15; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            final context = tester.element(find.byType(WavebreakApp));
            final container = ProviderScope.containerOf(context);
            container.read(languageProvider.notifier);
            final GoRouter router = container.read(routerProvider);
            router.go(shot.path);
            for (var i = 0; i < 25; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            await expectLater(
              find.byType(WavebreakApp),
              matchesGoldenFile(file),
            );
            // Let pending timers of the screen finish before teardown.
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 5));
            FlutterError.onError = originalOnError;
          });
        }
      }
    }
  }
}
