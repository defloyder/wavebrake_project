import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/app/app.dart';
import 'package:wavebreak/core/storage/prefs_store.dart';

import 'test_helpers.dart';

// Regression coverage for a real-device security bug: a product owner
// swiped the app away from Recents and reopened it, and account/
// subscription/connection-status content was visible and interactive
// for a stretch before any lock prompt appeared. The fix has two parts
// (see app_lock_gate.dart's own comments):
//  1. The lock decision is a synchronous field initializer
//     (_AppLockGateState._locked = _shouldLock()), computed the moment
//     the gate widget is built — never gated behind session bootstrap,
//     a network call, or any other async step. This test drives that
//     directly: pump exactly one frame (deliberately not pumpAndSettle,
//     since bootstrapSession's own async work is still in flight at
//     that point) and confirm the lock screen is already showing.
//  2. The resume-after-backgrounding grace period that used to let a
//     real close-and-reopen slip through unlocked shrank from 2 minutes
//     to 8 seconds — covered structurally by reading the constant back
//     via reflection-free means isn't practical here, so that half is
//     verified by code review + the constant's own doc comment; this
//     test focuses on the always-testable synchronous-first-frame half.
void main() {
  setUp(setUpTestEnvironment);

  testWidgets(
    'app lock covers the very first frame when enabled, before bootstrap resolves',
    (tester) async {
      await PrefsStore.setBool(PrefsStore.appLockEnabled, true);
      // A PIN alone is enough to make appLockAvailable() true without
      // ever touching the real LocalAuthentication plugin (unavailable
      // in the test environment) — see PinService.isSet /
      // BiometricService.isEnabled in app_lock_gate.dart's
      // appLockAvailable().
      await PrefsStore.setBool(PrefsStore.pinEnabled, true);

      await tester.pumpWidget(const ProviderScope(child: WavebreakApp()));
      // Exactly one frame — not pumpAndSettle, not even a second pump.
      // bootstrapSession() is still mid-flight at this point (it's a
      // FutureProvider-backed async chain), and the router's own
      // redirect logic hasn't necessarily resolved off /splash yet
      // either. If the lock screen only shows up on some LATER frame,
      // that's exactly the bug this test exists to catch.
      await tester.pump();

      expect(
        find.text('Unlock WAVEBREAK'),
        findsOneWidget,
        reason: 'the lock screen must already be covering the app on the '
            'very first frame when App Lock is enabled, not appear only '
            'after session/bootstrap state resolves',
      );
    },
  );

  testWidgets(
    'no lock screen on the first frame when App Lock is disabled',
    (tester) async {
      // Sanity check for the test above: confirms the assertion is
      // actually discriminating (would fail if the lock screen rendered
      // unconditionally regardless of the App Lock setting).
      await tester.pumpWidget(const ProviderScope(child: WavebreakApp()));
      await tester.pump();

      expect(find.text('Unlock WAVEBREAK'), findsNothing);
    },
  );
}
