import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/features/shared/toast.dart';

void main() {
  testWidgets('repeated taps never queue toasts', (tester) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: key,
      home: const Scaffold(body: SizedBox()),
    ));
    for (var i = 0; i < 10; i++) {
      showToast(key.currentState!, 'Серверы обновлены');
    }
    await tester.pump();
    expect(find.text('Серверы обновлены'), findsOneWidget);
    // A different message replaces it at once.
    showToast(key.currentState!, 'Перезапуск');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Перезапуск'), findsOneWidget);
    // After it is gone nothing else is waiting in the queue.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
