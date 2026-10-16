// A sheet of flags and the tints the UI takes from them — to eyeball.
//   flutter test test_screens/flags_sheet_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/core/theme/flag_colors.dart';
import 'package:wavebreak/features/shared/flag_icon.dart';

const codes = ['BG', 'GB', 'FR', 'SE', 'NL', 'CH', 'DE', 'IT', 'AE', 'TR', 'RU', 'FI', 'KZ', 'US', 'JP', 'BR'];

void main() {
  testWidgets('flags sheet', (tester) async {
    tester.view.physicalSize = const Size(880, 440);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: const Color(0xFF0B0B10),
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          for (final c in codes)
            SizedBox(
              width: 200,
              child: Row(children: [
                FlagIcon(countryCode: c, width: 44),
                const SizedBox(width: 8),
                Text(c, style: const TextStyle(color: Colors.white, fontSize: 14)),
                const SizedBox(width: 8),
                Container(width: 40, height: 22, color: accentColorFor(c)),
                Container(width: 40, height: 22, color: secondAccentFor(c) ?? Colors.transparent),
              ]),
            ),
        ]),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/flags.png'));
  });
}
