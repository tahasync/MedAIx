/// Sprint gating: a build only shows the epics its sprint has delivered.
/// These tests run at the real [kBuildSprint] (no override), so bumping the
/// build sprint is what un-gates a feature — nothing else.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/features.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';

import 'support/test_app.dart';

void main() {
  test('this build is Sprint 3: trends on, later epics off', () {
    const FeatureFlags f = FeatureFlags(kBuildSprint);
    expect(kBuildSprint, 3);
    expect(f.trends, isTrue);
    expect(f.wellness, isFalse);
    expect(f.meds, isFalse);
    expect(f.scan, isFalse);
    expect(f.doctorMatch, isFalse);
    expect(f.share, isFalse);
    expect(f.doctorPortal, isFalse);
    expect(f.reminders, isFalse);
  });

  test('flags switch on at their roadmap sprint', () {
    expect(const FeatureFlags(4).wellness, isTrue);
    expect(const FeatureFlags(8).meds, isFalse);
    expect(const FeatureFlags(9).meds, isTrue);
    expect(const FeatureFlags(9).scan, isFalse);
    expect(const FeatureFlags(10).scan, isTrue);
    expect(const FeatureFlags(11).doctorMatch, isTrue);
    expect(const FeatureFlags(12).share, isTrue);
    expect(const FeatureFlags(13).doctorPortal, isTrue);
    expect(const FeatureFlags(13).reminders, isTrue);
    expect(const FeatureFlags.all().sprint, kAllSprints);
  });

  testWidgets('the nav shows only delivered tabs', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(
      testApp(overrides: fakeOverrides(sprint: kBuildSprint)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingNav), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Meds'), findsNothing);
    expect(find.text('Wellness'), findsNothing);
  });

  testWidgets('Home offers upload and trends, no later-sprint tiles', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(
      testApp(overrides: fakeOverrides(sprint: kBuildSprint)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Upload report'), findsWidgets);
    expect(find.text('View trends'), findsOneWidget);
    expect(find.text('Check medicines'), findsNothing);
    expect(find.text('Scan medicine'), findsNothing);
    expect(find.text('Find a doctor'), findsNothing);
    expect(find.textContaining('Habit score'), findsNothing);
    expect(find.bySemanticsLabel('Reminders'), findsNothing);
  });

  testWidgets('a gated route lands on Home', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(
      testAppAt('/meds', overrides: fakeOverrides(sprint: kBuildSprint)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Medicine check'), findsNothing);
    expect(find.text('View trends'), findsOneWidget);
  });

  testWidgets('a delivered sub-route still opens', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(
      testAppAt(
        '/reports/trends',
        overrides: fakeOverrides(sprint: kBuildSprint),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('trend'), findsWidgets);
    expect(find.text('View trends'), findsNothing);
  });

  testWidgets('Settings hides reminders and sharing rows', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(
      testAppAt('/settings', overrides: fakeOverrides(sprint: kBuildSprint)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dark appearance'), findsOneWidget);
    expect(find.text('Profile and health details'), findsOneWidget);
    expect(find.text('Reminders'), findsNothing);
    expect(find.text('Records'), findsNothing);
    expect(find.text('Share with doctor'), findsNothing);
    expect(find.text('Doctor portal'), findsNothing);
  });

  testWidgets('a demo build (all sprints) shows all five tabs', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    for (final String tab in ['Home', 'Reports', 'Meds', 'Wellness', 'More']) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }
  });
}
