import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/router.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/data/repositories.dart';
import 'package:tahasync_medaix/features/reports/data/report_models.dart';
import 'package:tahasync_medaix/features/reports/ui/reports_screen.dart';

import 'support/test_app.dart';

Future<void> pumpAt(
  WidgetTester tester,
  String location, {
  List<Override> overrides = const <Override>[],
}) async {
  await usePhone(tester);
  await tester.pumpWidget(testAppAt(location, overrides: overrides));
  await tester.pumpAndSettle();
}

void main() {
  group('Reports list', () {
    testWidgets('renders every report with its status', (tester) async {
      await pumpAt(tester, AppRoutes.reports);

      expect(find.text('Reports'), findsWidgets);
      expect(find.text('3 reports'), findsOneWidget);
      expect(find.text('Blood test'), findsNWidgets(2));
      expect(find.text('Lipid profile'), findsOneWidget);
      expect(find.text('18 Oct 2026'), findsOneWidget);
      expect(find.byType(StatusLabel), findsNWidgets(3));
      expect(find.text('2 need attention'), findsOneWidget);
      expect(find.text('All normal'), findsNWidgets(2));
      expect(
        find.widgetWithText(PrimaryButton, 'Upload report'),
        findsOneWidget,
      );
    });

    testWidgets('empty state invites the first upload', (tester) async {
      await pumpAt(
        tester,
        AppRoutes.reports,
        overrides: fakeOverrides(
          reports: FakeReportsRepository(
            latency: Duration.zero,
            uploadDelay: Duration.zero,
            seed: const [],
          ),
        ),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No reports yet'), findsOneWidget);
      expect(find.text('Upload report'), findsOneWidget);
      expect(find.byType(StatusLabel), findsNothing);
    });

    testWidgets('error state says data is safe and offers Try again', (
      tester,
    ) async {
      await pumpAt(
        tester,
        AppRoutes.reports,
        overrides: <Override>[
          reportsRepositoryProvider.overrideWithValue(
            const FailingReportsRepository('Could not reach the service.'),
          ),
        ],
      );

      expect(find.byType(ErrorCard), findsOneWidget);
      expect(find.text('Couldn’t load your reports'), findsOneWidget);
      expect(
        find.textContaining('Your reports are still saved on your account.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('tapping a row opens the report', (tester) async {
      await pumpAt(tester, AppRoutes.reports);

      await tester.tap(find.text('Lipid profile'));
      await tester.pumpAndSettle();

      expect(find.text('In plain words'), findsOneWidget);
      expect(find.text('12 Aug 2026 · Lab report'), findsOneWidget);
      expect(find.text('Total cholesterol'), findsOneWidget);
      expect(find.text('168 mg/dL'), findsOneWidget);
    });

    testWidgets('no overflow at 320 dp with 200 % text', (tester) async {
      await usePhone(tester, size: const Size(320, 640));
      await tester.pumpWidget(testScreen(const ReportsScreen(), textScale: 2));
      await tester.pumpAndSettle();
      expect(find.text('Lipid profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Report', () {
    testWidgets('shows the summary, value cards and the trend button', (
      tester,
    ) async {
      await pumpAt(tester, AppRoutes.report(3));

      expect(find.text('Blood test'), findsOneWidget);
      expect(find.text('18 Oct 2026 · Lab report'), findsOneWidget);
      expect(find.text('In plain words'), findsOneWidget);
      expect(
        find.textContaining('Your blood sugar average is slightly high.'),
        findsOneWidget,
      );
      expect(find.text('HbA1c'), findsOneWidget);
      expect(find.text('6.4 %'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Slightly high'), findsOneWidget);
      expect(find.text('Normal'), findsNWidgets(2));
      expect(find.byType(StatusLabel), findsNWidgets(4));
      expect(find.text('View trend over time'), findsOneWidget);
    });

    testWidgets('Original text toggle reveals the OCR text', (tester) async {
      await pumpAt(tester, AppRoutes.report(3));

      expect(find.byType(SelectableText), findsNothing);
      await tester.tap(find.widgetWithText(AppChip, 'Original text'));
      await tester.pumpAndSettle();

      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining('HbA1c 6.4 % (4.0 - 6.0)'), findsOneWidget);
      expect(find.text('6.4 %'), findsNothing);

      await tester.tap(find.widgetWithText(AppChip, 'Plain words'));
      await tester.pumpAndSettle();
      expect(find.text('6.4 %'), findsOneWidget);
    });

    testWidgets('a report with no parsed values shows the full rewrite', (
      tester,
    ) async {
      final LabReport unparsed = LabReport(
        id: 9,
        title: 'Lab report',
        dateLabel: 'Today',
        status: ValueStatus.ok,
        statusText: 'Ready to read',
        summary: 'Your results look fine.',
        originalText: 'Some handwritten notes',
        simplifiedText:
            'Your results look fine. Nothing here needs a follow-up visit.',
        confidence: 48,
        hasSimplified: true,
      );
      await pumpAt(
        tester,
        AppRoutes.report(9),
        overrides: fakeOverrides(
          reports: FakeReportsRepository(
            latency: Duration.zero,
            uploadDelay: Duration.zero,
            seed: [unparsed],
          ),
        ),
      );

      expect(find.text('In plain words'), findsOneWidget);
      expect(
        find.text(
          'Your results look fine. Nothing here needs a follow-up visit.',
        ),
        findsOneWidget,
      );
      expect(find.byType(StatusLabel), findsNothing);
      expect(find.text('This photo was hard to read'), findsOneWidget);
      expect(find.text('View trend over time'), findsOneWidget);
    });

    testWidgets('missing report shows an error with a way back', (
      tester,
    ) async {
      await pumpAt(tester, AppRoutes.report(404));

      expect(find.byType(ErrorCard), findsOneWidget);
      expect(find.text('Couldn’t open this report'), findsOneWidget);
      expect(find.text('Back to reports'), findsOneWidget);
    });
  });

  group('Trends', () {
    testWidgets('renders the chart with a semantic label and the alert', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpAt(tester, '${AppRoutes.trends}?marker=HbA1c');

      expect(find.text('HbA1c trend'), findsOneWidget);
      expect(find.text('4 reports · Mar to Oct'), findsOneWidget);
      expect(
        find.bySemanticsLabel('HbA1c rose from 5.9 to 6.4 over 4 reports.'),
        findsOneWidget,
      );
      expect(find.text('Mar 5.9'), findsOneWidget);
      expect(find.text('Oct 6.4'), findsOneWidget);
      expect(find.text('Rising 3 times in a row'), findsOneWidget);
      expect(find.text('Find a specialist'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an unknown marker shows the empty state', (tester) async {
      await pumpAt(tester, '${AppRoutes.trends}?marker=Ferritin');

      expect(find.text('Ferritin trend'), findsOneWidget);
      expect(find.text('Not enough reports yet'), findsOneWidget);
      expect(find.text('Upload report'), findsOneWidget);
    });

    testWidgets('Find a specialist opens the doctor screen', (tester) async {
      await pumpAt(tester, '${AppRoutes.trends}?marker=HbA1c');

      await tester.tap(find.text('Find a specialist'));
      await tester.pumpAndSettle();
      expect(find.text('Find a doctor'), findsOneWidget);
    });

    testWidgets('without a marker, lists every tracked value', (tester) async {
      await pumpAt(tester, AppRoutes.trends);

      expect(find.text('Trends'), findsOneWidget);
      expect(find.text('4 reports'), findsOneWidget);
      expect(find.byType(AiInsightCard), findsOneWidget);
      expect(find.text('Worth a look'), findsOneWidget);
      expect(find.text('All values'), findsOneWidget);
      expect(find.text('HbA1c'), findsOneWidget);
      expect(find.text('Fasting glucose'), findsOneWidget);
      expect(find.text('LDL'), findsOneWidget);
      expect(find.text('Latest 6.4 % · 4 reports · Rising'), findsOneWidget);
      expect(find.text('Borderline'), findsOneWidget);
      expect(find.text('Normal'), findsNWidgets(2));
    });

    testWidgets('tapping a row opens that marker, Back returns to the list', (
      tester,
    ) async {
      await pumpAt(tester, AppRoutes.trends);

      await tester.tap(find.text('LDL'));
      await tester.pumpAndSettle();
      expect(find.text('LDL trend'), findsOneWidget);
      expect(find.text('3 reports · Mar to Oct'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Trends'), findsOneWidget);
      expect(find.text('All values'), findsOneWidget);
    });

    testWidgets('with fewer than two reports, explains what to do', (
      tester,
    ) async {
      await pumpAt(
        tester,
        AppRoutes.trends,
        overrides: [
          insightsRepositoryProvider.overrideWithValue(
            FakeInsightsRepository(latency: Duration.zero, reportsCount: 1),
          ),
        ],
      );

      expect(find.text('Not enough reports yet'), findsOneWidget);
      expect(find.textContaining('You have one report.'), findsOneWidget);
      expect(find.text('Upload report'), findsOneWidget);
      expect(find.byType(AiInsightCard), findsNothing);
    });
  });

  group('Doctor', () {
    testWidgets('picking a symptom shows the recommendation', (tester) async {
      await pumpAt(tester, AppRoutes.doctor);

      expect(find.text('What’s bothering you?'), findsOneWidget);
      expect(
        find.text('Pick a symptom to see which specialist fits.'),
        findsOneWidget,
      );
      expect(find.byType(AppChip), findsNWidgets(4));

      await tester.tap(find.text('Thirst and tiredness'));
      await tester.pumpAndSettle();

      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Endocrinologist'), findsOneWidget);
      expect(find.textContaining('Why: Your HbA1c is rising'), findsOneWidget);
      expect(find.text('Share my records'), findsOneWidget);
      expect(
        find.text('Pick a symptom to see which specialist fits.'),
        findsNothing,
      );

      await tester.tap(find.text('Chest pain'));
      await tester.pumpAndSettle();
      expect(find.text('Cardiologist'), findsOneWidget);
      expect(find.text('Endocrinologist'), findsNothing);
    });
  });
}
