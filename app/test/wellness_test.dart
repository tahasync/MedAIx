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

  testWidgets('renders the three habit cards and the score', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(wellnessScreen());
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.textContaining('Habit score'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    expect(find.textContaining('750 / 2400 ml'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);
    expect(
      find.text('4,120 / 6,000 · goal set for your condition'),
      findsOneWidget,
    );
    expect(find.text('Exercise'), findsOneWidget);
    expect(find.text('Not logged yet'), findsOneWidget);
    expect(find.byType(ProgressBar), findsNWidgets(2));
  });

  testWidgets('+250 ml updates the text and toasts', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(wellnessScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add 250 ml'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1000 / 2400 ml'), findsOneWidget);
    expect(find.text('Added 250 ml of water'), findsOneWidget);
  });

  testWidgets('Log walk shows Logged', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(wellnessScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log walk'));
    await tester.pumpAndSettle();

    expect(find.text('Log walk'), findsNothing);
    expect(find.text('Logged · 10 min'), findsOneWidget);
    expect(find.text('Walk'), findsOneWidget);
    expect(find.text('Walk logged'), findsOneWidget);
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

    expect(find.textContaining('5,320 / 6,000'), findsOneWidget);
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
    expect(find.byType(ProgressBar), findsOneWidget);
  });

  testWidgets('survives 200 % text scale without overflow', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(wellnessScreen(textScale: 2));
    await tester.pumpAndSettle();

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
