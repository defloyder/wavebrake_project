import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/core/i18n/app_strings.dart';
import 'package:wavebreak/features/settings/support_screen.dart';
import 'package:wavebreak/services/core_api/models.dart';

import 'test_helpers.dart';

void main() {
  setUp(setUpTestEnvironment);

  testWidgets('Support lists the mailbox and every ready-made request', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: mockCoreOverrides(),
      child: const MaterialApp(home: SupportScreen()),
    ));
    await tester.pump();

    const s = kEnglishStrings;
    expect(find.text(kSupportEmail), findsOneWidget);
    expect(kSupportEmail, 'wavebreak.support@gmail.com');
    for (final title in [s.tplNoConnect, s.tplSlow, s.tplSubscription, s.tplDevices, s.tplLogin, s.reportAProblem]) {
      expect(find.text(title), findsOneWidget);
    }
  });
}
