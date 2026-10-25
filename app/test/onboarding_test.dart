import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/features/onboarding/providers/onboarding_providers.dart';
import 'package:tahasync_medaix/features/onboarding/ui/onboarding_screen.dart';
import 'package:tahasync_medaix/features/profile/data/profile_repository.dart';
import 'package:tahasync_medaix/features/profile/providers/profile_form.dart';
import 'package:tahasync_medaix/features/profile/ui/profile_fields.dart';

import 'support/test_app.dart';

Future<FakeProfileRepository> _pump(
  WidgetTester tester, {
  PatientProfile? profile,
}) async {
  await usePhone(tester);
  final FakeProfileRepository profiles = FakeProfileRepository(
    latency: Duration.zero,
    seed: profile ?? accountOnlyProfile(),
  );
  await tester.pumpWidget(
    testApp(overrides: fakeOverrides(profileRepository: profiles)),
  );
  await tester.pumpAndSettle();
  return profiles;
}

/// The screen is a lazy list, so anything off-screen is not built yet.
/// Scrolls until [finder] is built and laid out; false when it never is.
Future<bool> _reveal(WidgetTester tester, Finder finder) async {
  // Let any caret-scroll animation from a focused field finish first.
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    final Finder scrollable = find.byType(Scrollable).first;
    // Items above the viewport are unbuilt too, so scan from the top.
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    try {
      await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
    } on StateError {
      return false;
    }
  }
  await tester.ensureVisible(finder.first);
  await tester.pump();
  return true;
}

/// Asserts [finder] exists (after scrolling it into view) or does not exist
/// anywhere in the list.
Future<void> _expect(
  WidgetTester tester,
  Finder finder, {
  bool present = true,
}) async {
  final bool found = await _reveal(tester, finder);
  expect(found, present, reason: '${finder.describeMatch(Plurality.one)}');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String label) =>
    _tap(tester, find.widgetWithText(FilledButton, label));

Finder _chip(String label) => find.widgetWithText(AppChip, label);

Future<void> _tapChip(WidgetTester tester, String label) =>
    _tap(tester, _chip(label).first);

/// The medicines Yes / No chips (the pregnancy question also has a "No").
Finder _medicinesChip(String label) =>
    find.descendant(of: find.byType(MedicinesQuestion), matching: _chip(label));

Future<bool> _chipSelected(WidgetTester tester, String label) async {
  await _reveal(tester, _chip(label));
  return tester.widget<AppChip>(_chip(label).first).selected;
}

Future<bool> _buttonEnabled(WidgetTester tester, String label) async {
  final Finder finder = find.widgetWithText(FilledButton, label);
  await _reveal(tester, finder);
  return tester.widget<FilledButton>(finder).onPressed != null;
}

Finder _switch(String label) => find.byWidgetPredicate(
  (widget) => widget is AppSwitch && widget.label == label,
);

Future<void> _enter(WidgetTester tester, Finder finder, String text) async {
  await _reveal(tester, finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

Future<String> _fieldText(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  return tester.widget<TextField>(finder).controller!.text;
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(OnboardingScreen)));

const Key _name = Key('onboarding-name');
const Key _medicines = Key('onboarding-medicines');
const Key _height = Key('onboarding-height');
const Key _weight = Key('onboarding-weight');
final Finder _inches = find.widgetWithText(TextField, 'Inches');

void main() {
  group('Screen 1 inside onboarding (no account basics on file)', () {
    testWidgets('a fresh profile starts at the account step without the nav', (
      tester,
    ) async {
      await _pump(tester, profile: kFreshProfile);

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(FloatingNav), findsNothing);
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Step 1 of 3 · Required'), findsOneWidget);
      expect(await _buttonEnabled(tester, 'Continue'), isFalse);
      // Screen 1 is required: no skip or back here.
      await _expect(tester, find.text('Skip for now'), present: false);
      await _expect(tester, find.text('Back'), present: false);
    });

    testWidgets('Continue unlocks once the six items are valid', (
      tester,
    ) async {
      await _pump(tester, profile: kFreshProfile);

      await _enter(tester, find.byKey(_name), 'Ada');
      _container(
        tester,
      ).read(onboardingProvider.notifier).setDateOfBirth(DateTime(1990, 5, 14));
      await tester.pumpAndSettle();
      await _tapChip(tester, 'Female');
      expect(await _buttonEnabled(tester, 'Continue'), isFalse);

      await _tap(tester, _switch('Agree to the Terms and Privacy Policy'));
      await _tap(tester, _switch('Agree to health data processing'));
      expect(await _buttonEnabled(tester, 'Continue'), isTrue);

      await _tapButton(tester, 'Continue');
      await _expect(tester, find.text('Your health basics'));
      await _expect(
        tester,
        find.text('Step 2 of 3 · All optional, one tap each'),
      );
      // Female → the pregnancy question is on.
      await _expect(tester, find.text('Are you pregnant or breastfeeding?'));
    });

    testWidgets('under 18 shows the adults-only message and stores nothing', (
      tester,
    ) async {
      await _pump(tester, profile: kFreshProfile);
      final DateTime now = DateTime.now();
      _container(tester)
          .read(onboardingProvider.notifier)
          .setDateOfBirth(DateTime(now.year - 17, now.month, now.day));
      await tester.pumpAndSettle();

      await _expect(tester, find.text(kUnderAgeMessage));
      expect(_container(tester).read(onboardingProvider).dateOfBirth, isNull);
    });
  });

  group('Screen 2 · Your health basics', () {
    testWidgets('starts here when Screen 1 is on file', (tester) async {
      await _pump(tester);

      expect(find.text('Your health basics'), findsOneWidget);
      expect(
        find.text('Step 2 of 3 · All optional, one tap each'),
        findsOneWidget,
      );
      await _expect(tester, find.text('Any ongoing conditions?'));
      await _expect(tester, find.text('Any allergies?'));
      await _expect(tester, find.text('Do you take any medicines regularly?'));
      for (final String option in kConditionOptions) {
        await _expect(tester, _chip(option));
      }
      await _expect(tester, _chip('Aspirin or NSAIDs'));
      await _expect(tester, find.text('Skip for now'));
      await _expect(tester, find.text('Back'), present: false);
    });

    testWidgets('None and Prefer not to say clear the other chips', (
      tester,
    ) async {
      await _pump(tester);

      await _tapChip(tester, 'Diabetes');
      await _tapChip(tester, 'Asthma');
      expect(await _chipSelected(tester, 'Diabetes'), isTrue);
      expect(await _chipSelected(tester, 'Asthma'), isTrue);

      // Two "None" chips (conditions, allergies): the first is conditions.
      await _tapChip(tester, 'None');
      expect(await _chipSelected(tester, 'None'), isTrue);
      expect(await _chipSelected(tester, 'Diabetes'), isFalse);
      expect(await _chipSelected(tester, 'Asthma'), isFalse);

      await _tapChip(tester, 'Prefer not to say');
      expect(await _chipSelected(tester, 'None'), isFalse);
      expect(await _chipSelected(tester, 'Prefer not to say'), isTrue);

      await _tapChip(tester, 'Hypertension');
      expect(await _chipSelected(tester, 'Prefer not to say'), isFalse);
      expect(await _chipSelected(tester, 'Hypertension'), isTrue);
    });

    testWidgets('Yes to medicines reveals the names field; No hides it', (
      tester,
    ) async {
      await _pump(tester);

      await _expect(tester, find.byKey(_medicines), present: false);
      await _tap(tester, _medicinesChip('Yes'));
      await _expect(tester, find.byKey(_medicines));
      await _expect(tester, find.textContaining('Scanning the packet'));
      await _enter(
        tester,
        find.byKey(_medicines),
        'Metformin 500 mg\nAspirin 75 mg',
      );
      await _tap(tester, _medicinesChip('No'));
      await _expect(tester, find.byKey(_medicines), present: false);
    });

    testWidgets('female sees the pregnancy question only', (tester) async {
      await _pump(tester, profile: accountOnlyProfile(sexAtBirth: 'female'));

      await _expect(tester, find.text('Are you pregnant or breastfeeding?'));
      await _expect(tester, _chip('Breastfeeding'));
      await _expect(
        tester,
        find.text('Any prostate or urinary problems?'),
        present: false,
      );
    });

    testWidgets('male 40+ sees the prostate question only', (tester) async {
      await _pump(
        tester,
        profile: accountOnlyProfile(sexAtBirth: 'male', age: 45),
      );

      await _expect(tester, find.text('Any prostate or urinary problems?'));
      await _expect(
        tester,
        find.text('Are you pregnant or breastfeeding?'),
        present: false,
      );
    });

    testWidgets('a younger male and "prefer not to say" see neither', (
      tester,
    ) async {
      await _pump(
        tester,
        profile: accountOnlyProfile(sexAtBirth: 'male', age: 30),
      );
      await _expect(
        tester,
        find.text('Any prostate or urinary problems?'),
        present: false,
      );
      await _expect(
        tester,
        find.text('Are you pregnant or breastfeeding?'),
        present: false,
      );

      await _pump(
        tester,
        profile: accountOnlyProfile(sexAtBirth: 'prefer_not_to_say'),
      );
      await _expect(
        tester,
        find.text('Any prostate or urinary problems?'),
        present: false,
      );
      await _expect(
        tester,
        find.text('Are you pregnant or breastfeeding?'),
        present: false,
      );
    });

    testWidgets('Skip for now lands on Home and marks onboarding seen', (
      tester,
    ) async {
      final FakeProfileRepository profiles = await _pump(tester);

      await _tap(tester, find.text('Skip for now'));

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(FloatingNav), findsOneWidget);
      // Nothing answered → nothing sent.
      expect(profiles.savedBodies, isEmpty);
    });

    testWidgets('Skip for now saves what was answered', (tester) async {
      final FakeProfileRepository profiles = await _pump(tester);

      await _tapChip(tester, 'Diabetes');
      await _tap(tester, find.text('Skip for now'));

      expect(find.byType(FloatingNav), findsOneWidget);
      expect(profiles.savedBodies.single, <String, dynamic>{
        'conditions': 'Diabetes',
      });
      expect(find.text('Details saved'), findsOneWidget);
    });
  });

  group('Screen 3 · About you', () {
    testWidgets('unit toggle converts and stores cm / kg', (tester) async {
      await _pump(tester);
      await _tapButton(tester, 'Continue');
      await _expect(tester, find.text('About you'));
      await _expect(tester, find.text('Step 3 of 3 · Optional'));

      await _enter(tester, find.byKey(_height), '170');
      await _enter(tester, find.byKey(_weight), '70');
      await _tapChip(tester, 'ft / lb');

      expect(await _fieldText(tester, find.byKey(_height)), '5');
      expect(await _fieldText(tester, _inches), '7');
      expect(await _fieldText(tester, find.byKey(_weight)), '154');

      // Typing in imperial stores metric.
      await _enter(tester, find.byKey(_height), '6');
      await _enter(tester, _inches, '0');
      await _enter(tester, find.byKey(_weight), '160');
      final OnboardingState s = _container(tester).read(onboardingProvider);
      expect(s.heightCm, 183);
      expect(s.weightKg, 72.6);

      await _tapChip(tester, 'cm / kg');
      expect(await _fieldText(tester, find.byKey(_height)), '183');
      expect(await _fieldText(tester, find.byKey(_weight)), '72.6');
    });

    testWidgets('out-of-range height blocks Finish with a plain message', (
      tester,
    ) async {
      await _pump(tester);
      await _tapButton(tester, 'Continue');

      await _enter(tester, find.byKey(_height), '20');
      await _tapButton(tester, 'Finish');

      expect(find.byType(OnboardingScreen), findsOneWidget);
      await _expect(
        tester,
        find.textContaining('Check your height and weight.'),
      );
      await _expect(
        tester,
        find.text(
          'Enter a height between 50 and 250 cm (1 ft 8 in to 8 ft 2 in).',
        ),
      );
    });

    testWidgets(
      'Finish saves the answers, shows the completion CTAs, and Upload '
      'lands on the upload route',
      (tester) async {
        final FakeProfileRepository profiles = await _pump(tester);

        await _tapChip(tester, 'Diabetes');
        await _tapChip(tester, 'Peanuts');
        await _tap(tester, _medicinesChip('Yes'));
        await _enter(
          tester,
          find.byKey(_medicines),
          'Metformin 500 mg, Aspirin 75 mg',
        );
        await _tapChip(tester, 'Pregnant');
        await _tapButton(tester, 'Continue');

        await _tap(tester, find.text('Track a condition'));
        await _enter(tester, find.byKey(_height), '170');
        await _enter(tester, find.byKey(_weight), '70');
        await _tapButton(tester, 'Finish');

        await _expect(tester, find.text('You’re all set'));
        await _expect(
          tester,
          find.widgetWithText(FilledButton, 'Upload your first report'),
        );
        await _expect(
          tester,
          find.widgetWithText(FilledButton, 'Skip for now'),
        );
        expect(find.byType(FloatingNav), findsNothing);

        expect(profiles.savedBodies.single, <String, dynamic>{
          'conditions': 'Diabetes',
          'allergies': 'Peanuts',
          'takes_medicines': true,
          'medications': 'Metformin 500 mg, Aspirin 75 mg',
          'pregnancy_status': 'pregnant',
          'first_goal': 'condition',
          'height_cm': 170.0,
          'weight_kg': 70.0,
        });

        await _tapButton(tester, 'Upload your first report');
        expect(find.byType(OnboardingScreen), findsNothing);
        expect(find.text('Upload report'), findsWidgets);
      },
    );

    testWidgets('completion "Skip for now" lands on Home', (tester) async {
      await _pump(tester);
      await _tapButton(tester, 'Continue');
      await _tapButton(tester, 'Finish');
      await _expect(tester, find.text('You’re all set'));

      await _tapButton(tester, 'Skip for now');
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(FloatingNav), findsOneWidget);
    });

    testWidgets('Back keeps what was chosen', (tester) async {
      await _pump(tester);
      await _tapChip(tester, 'Diabetes');
      await _tapButton(tester, 'Continue');
      await _expect(tester, find.text('About you'));

      await _tap(tester, find.text('Back'));
      await _expect(tester, find.text('Your health basics'));
      expect(await _chipSelected(tester, 'Diabetes'), isTrue);
    });
  });

  testWidgets('fits a 320 dp screen at 200 % text scale without overflow', (
    tester,
  ) async {
    await usePhone(tester, size: const Size(320, 640));
    await tester.pumpWidget(
      testScreen(
        const OnboardingScreen(),
        overrides: fakeOverrides(profile: kFreshProfile),
        size: const Size(320, 640),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    await _reveal(tester, find.widgetWithText(FilledButton, 'Continue'));
    expect(tester.takeException(), isNull);
  });
}
