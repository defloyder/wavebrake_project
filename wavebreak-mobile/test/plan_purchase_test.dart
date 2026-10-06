import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/core/i18n/app_strings.dart';
import 'package:wavebreak/features/shared/data_providers.dart';
import 'package:wavebreak/features/subscription/subscription_screen.dart';
import 'package:wavebreak/services/core_api/mock_backend.dart';
import 'package:wavebreak/services/core_api/models.dart';

import 'test_helpers.dart';

// P9: choosing a plan never grants it — the plan screen goes through
// PlanPurchase, which today sends the user to the administration; promo
// codes from Core change the shown prices.
void main() {
  setUp(setUpTestEnvironment);

  Future<MockCoreBackend> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mock = MockCoreBackend()
      ..subscription = const SubscriptionInfo(
          id: 'sub-1', status: 'expired', planId: 'old', planName: 'Old');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...mockCoreOverrides(mock),
        plansProvider.overrideWith((ref) async => mock.plans),
        subscriptionProvider.overrideWith((ref) => Stream.value(mock.subscription)),
      ],
      child: const MaterialApp(home: SubscriptionScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return mock;
  }

  testWidgets('choosing a plan asks to contact the administration, grants nothing',
      (tester) async {
    final mock = await open(tester);
    const s = kEnglishStrings;

    await tester.tap(find.text('WAVEBREAK Monthly'));
    await tester.pumpAndSettle();

    expect(find.text(s.planContactAdmin), findsOneWidget);
    expect(find.text(s.planContactSupport), findsOneWidget);
    expect(mock.subscription.planId, 'old', reason: 'no subscription created');
  });

  testWidgets('a promo code from Core shows the discounted price', (tester) async {
    await open(tester);
    const s = kEnglishStrings;
    expect(find.text('9 \$'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'spring 20');
    await tester.tap(find.text(s.promoApply));
    await tester.pumpAndSettle();

    expect(find.text('Promo code SPRING20: −20%'), findsOneWidget);
    expect(find.text('7.20 \$'), findsOneWidget);
    expect(find.text('9 \$'), findsOneWidget, reason: 'the old price, struck through');

    await tester.tap(find.text(s.promoRemove));
    await tester.pumpAndSettle();
    expect(find.text('7.20 \$'), findsNothing);
  });

  testWidgets('an unknown promo code says so', (tester) async {
    await open(tester);
    const s = kEnglishStrings;

    await tester.enterText(find.byType(TextField), 'NOPE');
    await tester.tap(find.text(s.promoApply));
    await tester.pumpAndSettle();

    expect(find.text(s.errPromoNotFound), findsOneWidget);
  });

  test('promo errors from Core map to their messages', () {
    expect(formatMoney(49900, 'RUB'), '499 ₽');
    expect(formatMoney(499, 'USD'), '4.99 \$');
  });
}
