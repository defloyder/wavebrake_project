import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/features/home/home_vitals.dart';

void main() {
  test('rate shows two significant digits', () {
    expect(formatRate(0.028), '28');
    expect(formatRate(0.0994), '99');
    expect(formatRate(0.113), '110');
    expect(formatRate(0.117), '120');
    expect(formatRate(0.998), '990');
    expect(formatRate(1.24), '1.2');
    expect(formatRate(24.6), '25');
  });

  testWidgets('a new value replaces the old one without the values between',
      (tester) async {
    Widget at(double? v) => Directionality(
          textDirection: TextDirection.ltr,
          child: AnimatedValue(
            value: v,
            format: (x) => '${x.round()} ms',
            style: const TextStyle(fontSize: 20),
          ),
        );
    await tester.pumpWidget(at(49));
    expect(find.text('49 ms'), findsOneWidget);
    // No clock in the tree (as with reduce motion): straight swap.
    await tester.pumpWidget(at(120));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining(RegExp(r'^(?!120)\d+ ms$')), findsNothing);
    }
    expect(find.text('120 ms'), findsOneWidget);
    await tester.pumpWidget(at(null));
    await tester.pumpAndSettle();
    expect(find.text('—'), findsOneWidget);
  });
}
