import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('two-column rows share height and keep visual order', (
    tester,
  ) async {
    await usePhone(tester, size: const Size(390, 600));
    await tester.pumpWidget(
      testScreen(
        const BentoGrid(
          children: [
            BentoTile(key: ValueKey('a'), child: Text('First')),
            BentoTile(
              key: ValueKey('b'),
              child: Text('Second\nA little taller'),
            ),
            BentoTile(
              key: ValueKey('wide'),
              span: 2,
              child: Text('Full width'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Rect first = tester.getRect(find.byKey(const ValueKey('a')));
    final Rect second = tester.getRect(find.byKey(const ValueKey('b')));
    final Rect wide = tester.getRect(find.byKey(const ValueKey('wide')));
    expect(first.height, second.height);
    expect(first.top, second.top);
    expect(first.right, lessThan(second.left));
    expect(wide.top, greaterThan(first.bottom));
    expect(wide.width, closeTo(390, 1));
  });

  testWidgets('keeps paired tiles at common phone widths', (tester) async {
    for (final double width in [360, 411]) {
      final Size size = Size(width, 600);
      await usePhone(tester, size: size);
      await tester.pumpWidget(
        testScreen(
          const BentoGrid(
            children: [
              BentoTile(key: ValueKey('left'), child: Text('Left')),
              BentoTile(key: ValueKey('right'), child: Text('Right')),
            ],
          ),
          size: size,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byKey(const ValueKey('left'))).right,
        lessThan(tester.getRect(find.byKey(const ValueKey('right'))).left),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('stacks below 340 dp and at large text scale', (tester) async {
    for (final (Size size, double scale) in [
      (const Size(320, 700), 1.0),
      (const Size(390, 700), 1.5),
    ]) {
      await usePhone(tester, size: size);
      await tester.pumpWidget(
        testScreen(
          const BentoGrid(
            children: [
              BentoTile(key: ValueKey('one'), child: Text('One')),
              BentoTile(key: ValueKey('two'), child: Text('Two')),
            ],
          ),
          size: size,
          textScale: scale,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byKey(const ValueKey('two'))).top,
        greaterThan(tester.getRect(find.byKey(const ValueKey('one'))).bottom),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('tappable tile exposes its label and responds to tap', (
    tester,
  ) async {
    var tapped = false;
    final semantics = tester.ensureSemantics();
    await usePhone(tester);
    await tester.pumpWidget(
      testScreen(
        BentoGrid(
          children: [
            BentoTile(
              semanticsLabel: 'Add a report',
              onTap: () => tapped = true,
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(BentoTile)).label,
      contains('Add a report'),
    );
    await tester.tap(find.byType(BentoTile));
    expect(tapped, isTrue);
    semantics.dispose();
  });
}
