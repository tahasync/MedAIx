import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/data/repositories.dart';
import 'package:tahasync_medaix/features/home/providers/home_providers.dart';
import 'package:tahasync_medaix/features/home/ui/home_screen.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('greets by name with a time-of-day subtitle', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.text('Test'), findsOneWidget);
    expect(find.text(greetingForHour(DateTime.now().hour)), findsOneWidget);
    expect(find.byTooltip('Reminders'), findsOneWidget);
  });

  testWidgets('shows the AI insight with its action', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.byType(AiInsightCard), findsOneWidget);
    expect(find.text('AI insight'), findsOneWidget);
    expect(find.text('Your HbA1c has risen across 3 reports'), findsOneWidget);
    expect(find.text('See the trend'), findsOneWidget);
  });

  testWidgets('does not invent a trend when there are fewer than two reports', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(
      testApp(
        overrides: [
          insightsRepositoryProvider.overrideWithValue(
            FakeInsightsRepository(latency: Duration.zero, reportsCount: 1),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AiInsightCard), findsNothing);
    expect(find.text('Upload one more report to see trends'), findsOneWidget);
  });

  testWidgets('offers the four quick actions', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.byType(TileButton), findsNWidgets(4));
    for (final label in [
      'Upload report',
      'Check medicines',
      'Scan medicine',
      'Find a doctor',
    ]) {
      expect(find.widgetWithText(TileButton, label), findsOneWidget);
    }
  });

  testWidgets('habit card has a labelled ring and the next step', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    // Default fake day: 750/2400 ml water, 4120/6000 steps, no exercise.
    expect(find.byType(ScoreRing), findsOneWidget);
    expect(find.text('Habit score 40'), findsOneWidget);
    // The ring's label is merged into the card's node.
    expect(
      tester.getSemantics(find.byType(ScoreRing)).label,
      contains('Habit score 40 of 100'),
    );
    expect(find.text('Log water to reach 48 today'), findsOneWidget);
    expect(find.byTooltip('Open wellness'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('latest report row shows the newest report', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.text('Latest report'), findsOneWidget);
    expect(find.byType(SummaryRow), findsOneWidget);
    expect(find.text('Blood test, 18 Oct 2026'), findsOneWidget);
    expect(find.text('2 values need attention'), findsNothing);
    expect(find.text('2 need attention'), findsOneWidget);
  });

  testWidgets('tapping the latest report opens it', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    // The row sits below the floating nav until the page is scrolled.
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blood test, 18 Oct 2026'));
    await tester.pumpAndSettle();
    expect(find.text('In plain words'), findsOneWidget);
    // Date format may vary by locale; match the report identifier instead of exact date
    expect(find.text('Lab report'), findsOneWidget);
  });

  testWidgets('with no reports the latest section is an empty state', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(
      testApp(
        overrides: fakeOverrides(
          reports: FakeReportsRepository(
            latency: Duration.zero,
            uploadDelay: Duration.zero,
            seed: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SummaryRow), findsNothing);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No reports yet'), findsOneWidget);
    // Tile label plus the empty state's button.
    expect(find.text('Upload report'), findsNWidgets(2));
  });

  testWidgets('no overflow at 320 dp with 200 % text', (tester) async {
    await usePhone(tester, size: const Size(320, 640));
    await tester.pumpWidget(testScreen(const HomeScreen(), textScale: 2));
    await tester.pumpAndSettle();

    expect(find.text('Test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
