import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/app/app.dart';
import 'package:wavebreak/core/storage/prefs_store.dart';
import 'package:wavebreak/core/storage/secure_store.dart';
import 'package:wavebreak/services/pin/pin_service.dart';

import 'test_helpers.dart';

Future<void> _type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d).last);
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _openLocked(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: WavebreakApp()));
  await tester.pump();
  expect(find.text('Unlock WAVEBREAK'), findsOneWidget);
}

/// A PIN as builds before this fix stored it: Keystore only, no length.
Future<void> _legacyPin(String pin) async {
  const salt = 'legacy-salt';
  await SecureStore.write('pin_salt', salt);
  await SecureStore.write('pin_hash', sha256.convert(utf8.encode('$salt:$pin')).toString());
  await PrefsStore.setBool(PrefsStore.pinEnabled, true);
}

void main() {
  setUp(() async {
    await setUpTestEnvironment();
    await const PinService().clear();
  });

  for (final pin in ['1234', '12345', '123456']) {
    testWidgets('a ${pin.length}-digit PIN unlocks on its last digit', (tester) async {
      await const PinService().setPin(pin);
      await _openLocked(tester);
      expect(find.text('Continue'), findsNothing);
      await _type(tester, pin);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Unlock WAVEBREAK'), findsNothing, reason: 'PIN $pin should unlock');
    });
  }

  testWidgets('a wrong 4-digit PIN says so at once', (tester) async {
    await const PinService().setPin('1234');
    await _openLocked(tester);
    await _type(tester, '9999');
    expect(find.text('Incorrect PIN'), findsOneWidget);
    expect(find.text('Unlock WAVEBREAK'), findsOneWidget);
    await _type(tester, '1234');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Unlock WAVEBREAK'), findsNothing);
  });

  testWidgets('a PIN from an older build still unlocks and moves out of Keystore', (tester) async {
    await _legacyPin('4321');
    await _openLocked(tester);
    expect(find.text('Continue'), findsOneWidget);
    await _type(tester, '4321');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Unlock WAVEBREAK'), findsNothing);
    expect(PrefsStore.getString(PrefsStore.pinHash), isNotNull);
  });

  testWidgets('older build: a wrong PIN is reported on Continue', (tester) async {
    await _legacyPin('4321');
    await _openLocked(tester);
    await _type(tester, '1111');
    expect(find.text('Incorrect PIN'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Incorrect PIN'), findsOneWidget);
  });

  testWidgets('a Keystore that never answers is reported, not a silent pad', (tester) async {
    await PrefsStore.setBool(PrefsStore.pinEnabled, true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) => call.method == 'read' ? Completer<Object?>().future : Future.value(null),
    );
    await _openLocked(tester);
    await _type(tester, '1234');
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.textContaining('Could not check the PIN'), findsOneWidget);
    // Let the app's other Keystore timeouts run out before teardown.
    await tester.pump(const Duration(seconds: 30));
  });
}
