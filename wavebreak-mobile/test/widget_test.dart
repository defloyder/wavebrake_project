import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/app/app.dart';

import 'test_helpers.dart';

void main() {
  setUp(setUpTestEnvironment);

  testWidgets(
      'unauthenticated launch with no prior choice lands on the welcome screen',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: WavebreakApp()),
    );
    // The ocean background and connect button run continuous ambient
    // animations by design, so pumpAndSettle would never return — pump a
    // bounded number of frames instead.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // A fresh install has never chosen guest-vs-account yet, so it lands
    // on that choice screen first — never gated on the network, since
    // "use my own link" must work even when Core is unreachable.
    expect(find.text('I already have an account'), findsOneWidget);
    expect(find.text('Continue with my own link'), findsOneWidget);
    // The wordmark is now the real brand asset image, not text.
    expect(
      find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.contains('wavebreak'),
      ),
      findsWidgets,
    );
  });
}
