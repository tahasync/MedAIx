import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/features/meds/ui/meds_screen.dart';
import 'package:tahasync_medaix/features/meds/ui/scan_screen.dart';

import 'support/test_app.dart';

const List<String> kThree = <String>[
  'Metformin 500 mg',
  'Ibuprofen 400 mg',
  'Warfarin 5 mg',
];

Widget medsScreen({List<String> seed = const <String>[]}) => testScreen(
  const MedsScreen(),
  overrides: fakeOverrides(
    meds: FakeMedsRepository(latency: Duration.zero, seed: seed),
  ),
);

/// Pumps a few frames without `pumpAndSettle` (the viewfinder sweep line
/// animates forever).
Future<void> pumpFrames(WidgetTester tester, [int frames = 4]) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('MedsScreen', () {
    testWidgets('empty state shows the reason and "Add first medicine"', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(medsScreen());
      await tester.pumpAndSettle();

      expect(find.text('Medicine check'), findsOneWidget);
      expect(find.text('No medicines added'), findsOneWidget);
      expect(
        find.text(
          'Add what you take. We’ll flag combinations that can cause harm.',
        ),
        findsOneWidget,
      );
      expect(find.text('Add first medicine'), findsOneWidget);
      expect(find.text('Check interactions'), findsNothing);
    });

    testWidgets('adding from the sheet adds a row and toasts', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(medsScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add first medicine'));
      await tester.pumpAndSettle();
      expect(find.text('Add a medicine'), findsOneWidget);

      await tester.tap(find.text('Metformin 500 mg'));
      await tester.pumpAndSettle();

      expect(find.text('Add a medicine'), findsNothing);
      expect(find.text('Metformin 500 mg'), findsOneWidget);
      expect(find.text('Medicine added'), findsOneWidget);
      expect(find.text('Add another medicine'), findsOneWidget);
      expect(find.byTooltip('Remove Metformin 500 mg'), findsOneWidget);
    });

    testWidgets('typing a name and tapping Add works too', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(medsScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add first medicine'));
      await tester.pumpAndSettle();

      final PrimaryButton before = tester.widget(
        find.widgetWithText(PrimaryButton, 'Add'),
      );
      expect(before.onPressed, isNull, reason: 'disabled while empty');

      await tester.enterText(find.byType(TextField), 'Vitamin D 1000 IU');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PrimaryButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.text('Vitamin D 1000 IU'), findsOneWidget);
      expect(find.text('Medicine added'), findsOneWidget);
    });

    testWidgets('"Check interactions" appears at two medicines', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(medsScreen(seed: kThree.sublist(0, 2)));
      await tester.pumpAndSettle();

      expect(find.text('Check interactions'), findsOneWidget);
      expect(find.text('Add another medicine'), findsOneWidget);
    });

    testWidgets('checking three seeded medicines shows the warning', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(medsScreen(seed: kThree));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check interactions'));
      await tester.pumpAndSettle();

      expect(find.text('Ibuprofen with warfarin'), findsOneWidget);
      expect(
        find.textContaining('raise the risk of serious bleeding'),
        findsOneWidget,
      );
      expect(find.text('Ask a doctor'), findsWidgets);
    });

    testWidgets('all-clear card when no risky combinations', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(
        medsScreen(seed: const ['Metformin 500 mg', 'Amlodipine 5 mg']),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check interactions'));
      await tester.pumpAndSettle();

      expect(find.text('No risky combinations found'), findsOneWidget);
      expect(
        find.text('Nothing here needs a doctor’s attention.'),
        findsOneWidget,
      );
    });

    testWidgets('add button is disabled at three medicines', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(medsScreen(seed: kThree));
      await tester.pumpAndSettle();

      final GhostButton add = tester.widget(
        find.widgetWithText(GhostButton, 'Add another medicine'),
      );
      expect(add.onPressed, isNull);
    });

    testWidgets('removing a medicine clears the previous warning', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(medsScreen(seed: kThree));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check interactions'));
      await tester.pumpAndSettle();
      expect(find.text('Ibuprofen with warfarin'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove Warfarin 5 mg'));
      await tester.pumpAndSettle();

      expect(find.text('Warfarin 5 mg'), findsNothing);
      expect(find.text('Ibuprofen with warfarin'), findsNothing);
      expect(find.text('Removed Warfarin 5 mg'), findsOneWidget);
    });

    testWidgets('fits 320 dp without overflow', (tester) async {
      await usePhone(tester, size: const Size(320, 640));
      await tester.pumpWidget(medsScreen(seed: kThree));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check interactions'));
      await tester.pumpAndSettle();

      expect(find.text('Ibuprofen with warfarin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ScanScreen', () {
    testWidgets('permission card → viewfinder → capture → match', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(
        testScreen(
          const ScanScreen(),
          overrides: fakeOverrides(
            meds: FakeMedsRepository(latency: Duration.zero),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Camera access needed'), findsOneWidget);
      expect(find.text('Type the name instead'), findsOneWidget);

      await tester.tap(find.text('Allow camera'));
      await pumpFrames(tester);

      expect(find.text('Point at the packet'), findsOneWidget);
      expect(find.text('Hold steady…'), findsOneWidget);
      expect(find.text('Capture packet'), findsOneWidget);

      await tester.tap(find.text('Capture packet'));
      await pumpFrames(tester);

      expect(find.text('Panadol 500 mg'), findsOneWidget);
      expect(find.text('Matches your list'), findsOneWidget);
      expect(
        find.text('Paracetamol 500 mg. Safe with your current medicines.'),
        findsOneWidget,
      );
      expect(find.text('Add to my medicines'), findsOneWidget);
      // The sweep animation stops once matched, so this settles.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
