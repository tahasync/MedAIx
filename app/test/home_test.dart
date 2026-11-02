import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/data/repositories.dart';
import 'package:tahasync_medaix/features/home/providers/home_providers.dart';
import 'package:tahasync_medaix/features/home/ui/home_screen.dart';

import 'support/test_app.dart';

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'en_US';
  });

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

    expect(
      find.byKey(const ValueKey<String>('home-insight-tile')),
      findsOneWidget,
    );
    expect(find.text('Automated insight'), findsOneWidget);
    expect(find.text('Sample HbA1c trend'), findsOneWidget);
    expect(find.text('See HbA1c trend'), findsOneWidget);
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

    expect(find.text('Automated insight'), findsNothing);
    expect(find.text('Upload one more report to see trends'), findsOneWidget);
  });

  testWidgets('shows report and trend actions in the bento grid', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.byType(BentoGrid), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('add-report-tile')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('trends-tile')), findsOneWidget);
    expect(find.text('Add a report'), findsOneWidget);
    expect(find.text('See my trends'), findsOneWidget);
  });

  testWidgets('habit card shows its score, progress and next step', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    // Default fake day: 750/2400 ml water, 4120/6000 steps, no exercise.
    expect(find.byType(ScoreRing), findsNothing);
    expect(find.text('Habit score 40'), findsOneWidget);
    expect(find.byType(ProgressBar), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(ProgressBar)).label,
      contains('Habit score progress: 40 of 100'),
    );
    expect(
      find.text('Next: log water toward your daily goal.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Open wellness'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('latest report row shows the newest report', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.text('Latest report'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('latest-report-tile')),
      findsOneWidget,
    );
    expect(find.textContaining('Blood test'), findsOneWidget);
    expect(find.text('2 need attention'), findsOneWidget);
  });

  testWidgets('tapping the latest report opens it', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    // The row sits below the floating nav until the page is scrolled.
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Blood test'));
    await tester.pumpAndSettle();
    expect(find.text('In plain words'), findsOneWidget);
    // The fake report title appears in the header subtitle with its date.
    expect(find.text('Blood test · 18 Oct 2026'), findsOneWidget);
  });

  testWidgets('with no reports shows only the first-run hero', (tester) async {
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

    expect(find.byType(BentoGrid), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('first-run-hero')),
      findsOneWidget,
    );
    expect(find.text('Add your first report'), findsOneWidget);
    expect(find.text('Add a report'), findsOneWidget);
    expect(find.text('See my trends'), findsNothing);
    expect(find.text('Latest report'), findsNothing);
    expect(find.byType(SummaryRow), findsNothing);
  });

  testWidgets('no overflow at 320 dp with 200 % text', (tester) async {
    await usePhone(tester, size: const Size(320, 640));
    await tester.pumpWidget(testScreen(const HomeScreen(), textScale: 2));
    await tester.pumpAndSettle();

    expect(find.text('Test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
