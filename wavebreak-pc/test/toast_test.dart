import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/features/shared/notice.dart';
import 'package:wavebreak/features/shared/toast.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        builder: (context, child) => NoticeHost(child: child),
        home: const Scaffold(body: SizedBox()),
      ));

  testWidgets('repeated taps never queue notices', (tester) async {
    await pumpApp(tester);
    for (var i = 0; i < 10; i++) {
      showToast(null, 'Серверы обновлены');
    }
    await tester.pump();
    expect(find.text('Серверы обновлены'), findsOneWidget);
    // A different message replaces it at once.
    showToast(null, 'Перезапуск');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Перезапуск'), findsOneWidget);
    expect(find.text('Серверы обновлены'), findsNothing);
    // After it is gone nothing else is waiting.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(NoticeCard), findsNothing);
  });

  testWidgets('a notice sits at the top and closes on tap', (tester) async {
    await pumpApp(tester);
    var acted = false;
    showNotice('Доступно обновление',
        kind: NoticeKind.info,
        actionLabel: 'Обновить',
        onAction: () => acted = true,
        duration: const Duration(seconds: 10));
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byType(NoticeCard));
    expect(card.top, lessThan(100));
    await tester.tap(find.text('Обновить'));
    await tester.pumpAndSettle();
    expect(acted, isTrue);
    expect(find.byType(NoticeCard), findsNothing);

    showNotice('Нет интернета', kind: NoticeKind.warning);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Нет интернета'));
    await tester.pumpAndSettle();
    expect(find.byType(NoticeCard), findsNothing);
  });
}
