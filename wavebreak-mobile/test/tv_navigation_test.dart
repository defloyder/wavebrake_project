import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/features/shell/app_shell.dart';
import 'package:wavebreak/features/tv/tv_scale.dart';

void main() {
  group('rail: ↑/↓ step through its items only (owner, 15.10)', () {
    const items = ['home', 'servers', 'settings', 'test', 'metrics'];

    test('next and previous', () {
      expect(railStep(items, 'settings', true), 'test');
      expect(railStep(items, 'settings', false), 'servers');
    });

    test('stays put at the ends instead of leaving the rail', () {
      expect(railStep(items, 'home', false), isNull);
      expect(railStep(items, 'metrics', true), isNull);
    });

    test('a node outside the rail moves nowhere', () {
      expect(railStep(items, 'chart', true), isNull);
    });
  });

  group('remote scrolls a page without controls', () {
    test('40 % of the viewport per press', () {
      expect(scrollTarget(0, 500, 0, 2000, true), 200);
      expect(scrollTarget(600, 500, 0, 2000, false), 400);
    });

    test('clamped to the ends; nothing at an end', () {
      expect(scrollTarget(1900, 500, 0, 2000, true), 2000);
      expect(scrollTarget(2000, 500, 0, 2000, true), isNull);
      expect(scrollTarget(0, 500, 0, 2000, false), isNull);
    });
  });

  testWidgets('TV canvas: 960×540 lays out at 1200×675 and fills the screen',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    Size? seen;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(960, 540), devicePixelRatio: 2),
      child: TvScale(
        child: Builder(builder: (context) {
          seen = MediaQuery.sizeOf(context);
          return const SizedBox.expand();
        }),
      ),
    ));
    expect(seen, const Size(1200, 675));
    expect(tester.getSize(find.byType(TvScale)), const Size(960, 540));
  });
}
