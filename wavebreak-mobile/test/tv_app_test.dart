import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavebreak/core/auth/session_controller.dart';
import 'package:wavebreak/core/storage/prefs_store.dart';
import 'package:wavebreak/features/shared/data_providers.dart';
import 'package:wavebreak/features/tv/tv_app.dart';
import 'package:wavebreak/services/core_api/models.dart';
import 'package:wavebreak/services/vpn/connection_manager.dart';

const _server = LocationItem(
    id: 'tv-server',
    countryCode: 'TR',
    country: 'Turkey',
    city: 'Istanbul (Direct)',
    available: true);

class _Session extends SessionController {
  @override
  SessionState build() => const SessionState(
      phase: SessionPhase.authenticated,
      user: UserProfile(id: 'tv-user', email: 'tv@example.test'));
}

class _Connection extends ConnectionManager {
  @override
  WbConnectionState build() =>
      const WbConnectionState(status: ConnectionStatus.idle, location: _server);
  @override
  Future<void> reconcileWithSystem() async {}
  @override
  void hydrateLocations(List<LocationItem> locations) {}
  @override
  Future<void> toggle({required bool subscriptionActive}) async {
    if (!subscriptionActive) return;
    state = state.copyWith(
        status: state.status == ConnectionStatus.connected
            ? ConnectionStatus.idle
            : ConnectionStatus.connected);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    PrefsStore.init(await SharedPreferences.getInstance());
  });

  testWidgets('remote Select activates focused control; arrow moves focus',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.select):
              const ActivateIntent()
        },
        home: Scaffold(
            body: Column(children: [
          TvButton(
              label: 'First', autofocus: true, onPressed: () => selected = 1),
          TvButton(label: 'Second', onPressed: () => selected = 2),
        ]))));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(selected, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(selected, 2);
  });

  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080)
  ]) {
    testWidgets('login and TV dashboard fit $size with remote navigation',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester
          .pumpWidget(const ProviderScope(child: MaterialApp(home: TvLogin())));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // This is a separate app/session, not an update to the login scope.
      // Dispose its container and text-field focus before adding overrides.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(ProviderScope(overrides: [
        sessionControllerProvider.overrideWith(_Session.new),
        connectionManagerProvider.overrideWith(_Connection.new),
        locationsProvider.overrideWith((ref) async => [_server]),
        subscriptionProvider.overrideWith(
            (ref) => Stream.value(const SubscriptionInfo(status: 'active'))),
      ], child: const WavebreakTvApp()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      await tester.tap(find.text('Locations'));
      await tester.pumpAndSettle();
      expect(find.text('Turkey · Istanbul (Direct)'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('tv@example.test'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
