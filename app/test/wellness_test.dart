import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/features/wellness/ui/wellness_screen.dart';
import 'package:tahasync_medaix/features/wellness/data/wellness_repository.dart';

import 'support/test_app.dart';

Widget wellnessScreen({double textScale = 1, WellnessDay? seed}) => testScreen(
  const WellnessScreen(),
  textScale: textScale,
  overrides: fakeOverrides(
    wellness: FakeWellnessRepository(latency: Duration.zero, seed: seed),
  ),
);

void main() {
  test('formatThousands adds separators', () {
    expect(formatThousands(0), '0');
    expect(formatThousands(999), '999');
    expect(formatThousands(4120), '4,120');
    expect(formatThousands(1234567), '1,234,567');
  });

  testWidgets('shows the daily log, progress and practical habit cards', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(wellnessScreen());
    await tester.pumpAndSettle();

    expect(find.text('Wellness'), findsOneWidget);
    expect(find.text('Your daily log'), findsOneWidget);
    expect(find.text('Today’s progress'), findsOneWidget);
    expect(find.text('Habit score 40%'), findsOneWidget);
    expect(
      find.text('Based on habits you log here; it is not a health assessment.'),
      findsOneWidget,
    );
    expect(find.text('Water'), findsOneWidget);
    expect(find.textContaining('750 / 2,400 ml'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);
    expect(
      find.text('4,120 / 6,000 steps · goal set for your condition'),
      findsOneWidget,
    );
    expect(find.text('Movement'), findsNWidgets(2));
    expect(find.text('No activity logged today'), findsOneWidget);
    expect(find.byType(ProgressBar), findsNWidgets(3));
  });

  testWidgets('+250 ml updates the text and toasts', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(wellnessScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add 250 ml'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1,000 / 2,400 ml'), findsOneWidget);
    expect(find.text('Added 250 ml of water'), findsOneWidget);
  });

  testWidgets('movement entries record the entered activity and minutes', (
    tester,
  ) async {
    await usePhone(tester, size: const Size(390, 1200));
    await tester.pumpWidget(wellnessScreen());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Log activity'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Log activity'));
    await tester.pumpAndSettle();

    final List<TextField> fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    await tester.enterText(find.byWidget(fields[0]), 'Stretching');
    await tester.enterText(find.byWidget(fields[1]), '20');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Save activity'));
    await tester.pumpAndSettle();

    expect(find.text('20 min logged today'), findsOneWidget);
    expect(find.text('Log activity'), findsOneWidget);
    expect(find.text('Stretching logged'), findsOneWidget);

    await tester.tap(find.text('Log activity'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '15');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Save activity'));
    await tester.pumpAndSettle();
    expect(find.text('35 min logged today'), findsOneWidget);
  });

  testWidgets('logs a validated step entry', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(wellnessScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Log steps'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1200');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Log steps'));
    await tester.pumpAndSettle();

    expect(find.textContaining('5,320 / 6,000 steps'), findsOneWidget);
    expect(find.text('Added 1,200 steps'), findsOneWidget);
  });

  testWidgets('respects a clinician-set fluid limit without an estimate', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(
      wellnessScreen(
        seed: const WellnessDay(
          waterMl: 500,
          waterGoalMl: null,
          steps: 1000,
          stepGoal: 4000,
          exerciseLabel: null,
          stepGoalNote: 'A lower starting goal based on your saved condition.',
          waterGoalNote:
              'Follow your clinician’s fluid limit; no estimate is shown.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('500 ml logged'), findsOneWidget);
    expect(find.textContaining('no estimate is shown'), findsOneWidget);
    expect(find.byType(ProgressBar), findsNWidgets(2));
  });

  testWidgets('survives 200 % text scale without overflow', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(wellnessScreen(textScale: 2));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Water'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    expect(find.text('Water'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits 320 dp at 200 % text scale', (tester) async {
    await usePhone(tester, size: const Size(320, 640));
    await tester.pumpWidget(wellnessScreen(textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
