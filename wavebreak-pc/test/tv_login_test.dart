import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/core/auth/session_controller.dart';
import 'package:wavebreak/features/settings/device_login_approve.dart';
import 'package:wavebreak/features/tv/tv_login_screen.dart';

import 'test_helpers.dart';

void main() {
  group('code from what the TV shows', () {
    test('its QR (Core address)', () {
      expect(deviceLoginCode('https://core.wavebreak.com.tr/v1/device-login/ABCD2345'),
          'ABCD2345');
      expect(deviceLoginCode('https://api.wavebreak.com.tr/v1/device-login/abcd2345?x=1'),
          'ABCD2345');
    });

    test('typed by hand, any case, with a dash', () {
      expect(deviceLoginCode(' abcd-2345 '), 'ABCD2345');
      expect(deviceLoginCode('abcd-2345', allowBare: false), isNull);
    });

    test('anything else is not a code', () {
      expect(deviceLoginCode('vless://id@host:443#x'), isNull);
      expect(deviceLoginCode('https://core.wavebreak.com.tr/v1/share/abc'), isNull);
      expect(deviceLoginCode('ABC'), isNull);
    });
  });

  testWidgets('TV shows the code and signs in once the phone approves',
      (tester) async {
    await setUpTestEnvironment();
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.pumpWidget(ProviderScope(
      overrides: mockCoreOverrides(),
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context);
        return const MaterialApp(home: TvLoginScreen());
      }),
    ));
    // The device name comes from a platform plugin that times out here.
    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    // The mock's code, shown for typing on a PC as well as in the QR.
    expect(find.text('MOCK-2345'), findsOneWidget);

    // The mock approves at the first poll (interval 3 s).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(sessionControllerProvider).phase,
        SessionPhase.authenticated);

    await tester.pumpWidget(const SizedBox());
    // Post-sign-in work (profile, device registration) has its own timers.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
  });
}
