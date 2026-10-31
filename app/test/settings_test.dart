import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/features/auth/ui/sign_in_screen.dart';
import 'package:tahasync_medaix/features/profile/providers/profile_providers.dart';
import 'package:tahasync_medaix/features/profile/ui/profile_screen.dart';
import 'package:tahasync_medaix/features/reports/data/reports_repository.dart';
import 'package:tahasync_medaix/features/reports/providers/reports_providers.dart';
import 'package:tahasync_medaix/features/settings/providers/settings_providers.dart';
import 'package:tahasync_medaix/features/settings/ui/reminders_screen.dart';
import 'package:tahasync_medaix/features/settings/ui/settings_screen.dart';

import 'support/test_app.dart';

/// Brings a lazily built list item on screen and lays it out before any
/// tap reads its position.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  // Let any caret-scroll animation from a focused field finish first.
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    final Finder scrollable = find.byType(Scrollable).first;
    // Items above the viewport are unbuilt too, so scan from the top.
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _tapText(WidgetTester tester, String label) async {
  final Finder finder = find.text(label);
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final Finder button = find.widgetWithText(FilledButton, label);
  await _reveal(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Finder _switch(String label) => find.byWidgetPredicate(
  (widget) => widget is AppSwitch && widget.label == label,
);

ProviderContainer _container(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)));

void main() {
  group('Settings', () {
    testWidgets('groups and rows render', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(testAppAt('/settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      for (final label in const [
        'Preferences',
        'Records',
        'Account',
        'Help and support',
        'Reminders',
        'Dark appearance',
        'Follow system theme',
        'Share with doctor',
        'Doctor portal',
        'Profile and health details',
        'Export my data',
        'Sign out',
        'Delete my data',
        'Frequently asked questions',
        'Troubleshooting',
        'Contact support',
      ]) {
        await _reveal(tester, find.text(label));
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('Dark appearance switch flips the theme mode', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(testAppAt('/settings'));
      await tester.pumpAndSettle();

      final ProviderContainer container = _container(tester, SettingsScreen);
      expect(container.read(themeModeProvider), ThemeMode.system);

      await tester.tap(_switch('Dark appearance'));
      await tester.pumpAndSettle();
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(
        tester.widget<AppSwitch>(_switch('Follow system theme')).value,
        isFalse,
      );

      await tester.tap(_switch('Dark appearance'));
      await tester.pumpAndSettle();
      expect(container.read(themeModeProvider), ThemeMode.light);

      await tester.tap(_switch('Follow system theme'));
      await tester.pumpAndSettle();
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    testWidgets('Export shows a toast', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(testAppAt('/settings'));
      await tester.pumpAndSettle();

      await _tapText(tester, 'Export my data');
      expect(
        find.text('Export is coming soon. Your data stays on your account.'),
        findsOneWidget,
      );
    });

    testWidgets('Sign out asks first, then returns to sign-in', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(testAppAt('/settings'));
      await tester.pumpAndSettle();

      await _tapText(tester, 'Sign out');
      expect(find.text('Sign out of MedAIx?'), findsOneWidget);
      expect(
        find.text('Your reports stay saved on your account.'),
        findsOneWidget,
      );

      await _tapText(tester, 'Stay signed in');
      expect(find.text('Sign out of MedAIx?'), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);

      await _tapText(tester, 'Sign out');
      await _tapButton(tester, 'Sign out');

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(FloatingNav), findsNothing);
    });

    testWidgets('Delete my data asks first, then confirms with a toast', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(
        testAppAt('/settings', overrides: fakeOverrides(onboardingSeen: true)),
      );
      await tester.pumpAndSettle();

      await _tapText(tester, 'Delete my data');
      expect(find.text('Delete your health details?'), findsOneWidget);

      await _tapText(tester, 'Keep my data');
      expect(find.text('Delete your health details?'), findsNothing);

      await _tapText(tester, 'Delete my data');
      await _tapButton(tester, 'Delete my data');

      expect(find.text('Your details were deleted'), findsOneWidget);
    });

    testWidgets('help rows open an info sheet', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(testAppAt('/settings'));
      await tester.pumpAndSettle();

      await _tapText(tester, 'Troubleshooting');
      expect(find.text('Troubleshooting'), findsNWidgets(2));
      expect(find.widgetWithText(FilledButton, 'Close'), findsOneWidget);
      await _tapButton(tester, 'Close');
      expect(find.text('Troubleshooting'), findsOneWidget);
    });
  });

  group('Reminders', () {
    testWidgets('switches persist through the settings repository', (
      tester,
    ) async {
      await usePhone(tester);
      final FakeSettingsRepository settings = FakeSettingsRepository();
      await tester.pumpWidget(
        testAppAt(
          '/settings/reminders',
          overrides: fakeOverrides(settings: settings),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RemindersScreen), findsOneWidget);
      expect(find.text('Take medicines'), findsOneWidget);
      expect(find.text('Every day at 8:00 am'), findsOneWidget);
      expect(find.text('Drink water'), findsOneWidget);
      expect(find.text('Doctor follow-up'), findsOneWidget);
      expect(
        tester.widget<AppSwitch>(_switch('Doctor follow-up')).value,
        isFalse,
      );

      await tester.tap(_switch('Doctor follow-up'));
      await tester.pumpAndSettle();
      expect(settings.reminders.followUp, isTrue);
      expect(
        tester.widget<AppSwitch>(_switch('Doctor follow-up')).value,
        isTrue,
      );

      await tester.tap(_switch('Take medicines'));
      await tester.pumpAndSettle();
      expect(settings.reminders.medicines, isFalse);
      expect(settings.reminders.water, isTrue);
    });
  });

  group('Profile', () {
    testWidgets('read rows show stored values', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(testAppAt('/settings/profile'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Used to tailor goals and alerts'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('170 cm'), findsOneWidget);
      expect(find.text('70 kg'), findsOneWidget);
      expect(find.text('Diabetes'), findsOneWidget);
      expect(find.text('Peanuts'), findsOneWidget);
      expect(find.textContaining('· 30'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Edit details'), findsOneWidget);
    });

    testWidgets('health-data deletion explains which records are removed', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(testAppAt('/settings/profile'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Delete my health data'));
      await _tapButton(tester, 'Delete my health data');
      await tester.pumpAndSettle();

      expect(find.text('Delete your health data?'), findsOneWidget);
      expect(find.textContaining('reports, wellness logs'), findsOneWidget);
      expect(find.textContaining('Your name and email stay.'), findsOneWidget);
    });

    test('deleting health data clears cached report history', () async {
      final FakeReportsRepository reports = FakeReportsRepository(
        latency: Duration.zero,
        uploadDelay: Duration.zero,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: fakeOverrides(reports: reports),
      );
      addTearDown(container.dispose);
      final int reportId = (await reports.listReports()).first.id;
      await container.read(reportDetailProvider(reportId).future);

      expect(
        await container.read(profileEditorProvider.notifier).delete(),
        isTrue,
      );

      expect(await reports.listReports(), isEmpty);
      await expectLater(
        container.read(reportDetailProvider(reportId).future),
        throwsA(isA<RepositoryException>()),
      );
    });

    testWidgets('validation blocks an empty name; saving shows a toast', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(testAppAt('/settings/profile'));
      await tester.pumpAndSettle();

      await _tapButton(tester, 'Edit details');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-name')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('profile-name')), '');
      await _tapButton(tester, 'Save details');
      expect(find.text('Enter your name.'), findsOneWidget);
      expect(find.text('Details saved'), findsNothing);

      await tester.enterText(find.byKey(const Key('profile-name')), 'Ada');
      await _tapButton(tester, 'Save details');

      expect(find.text('Details saved'), findsOneWidget);
      expect(find.byKey(const Key('profile-name')), findsNothing);
      expect(find.text('Ada'), findsOneWidget);
    });

    testWidgets('Cancel returns to read mode without saving', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(testAppAt('/settings/profile'));
      await tester.pumpAndSettle();

      await _tapButton(tester, 'Edit details');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        'Unsaved name',
      );
      await _tapText(tester, 'Cancel');

      // Cancel leaves the stored name unchanged.
      expect(find.text('Test'), findsOneWidget);
      expect(find.text('Unsaved name'), findsNothing);
    });

    testWidgets('fits a 320 dp screen in edit mode', (tester) async {
      await usePhone(tester, size: const Size(320, 640));
      await tester.pumpWidget(
        testScreen(const ProfileScreen(), size: const Size(320, 640)),
      );
      await tester.pumpAndSettle();

      await _tapButton(tester, 'Edit details');
      await tester.ensureVisible(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
