import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/brand/brand.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/features/auth/data/auth_gateway.dart';
import 'package:tahasync_medaix/features/auth/providers/auth_providers.dart';
import 'package:tahasync_medaix/features/auth/providers/sign_up_providers.dart';
import 'package:tahasync_medaix/features/auth/ui/sign_in_screen.dart';
import 'package:tahasync_medaix/features/onboarding/ui/onboarding_screen.dart';
import 'package:tahasync_medaix/features/profile/data/profile_repository.dart';
import 'package:tahasync_medaix/features/profile/providers/profile_form.dart';

import 'support/test_app.dart';

/// A gateway whose email sign-in fails with a user-safe message.
class _RejectingGateway extends FakeAuthGateway {
  _RejectingGateway() : super(session: null);

  int signInCalls = 0;

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    return const AuthResult(message: 'That email or password is incorrect.');
  }
}

Finder _signInButton() => find.widgetWithText(FilledButton, 'Sign in');
Finder _createButton() => find.widgetWithText(FilledButton, 'Create account');

Finder _switch(String label) => find.byWidgetPredicate(
  (widget) => widget is AppSwitch && widget.label == label,
);

/// Brings a lazily built list item on screen and lays it out before any
/// tap reads its position.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    final Finder scrollable = find.byType(Scrollable).first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SignInScreen)));

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<FilledButton>(button).onPressed != null;

Future<void> _openCreateAccount(WidgetTester tester) async {
  await _tap(tester, find.text('New here? Create an account'));
  expect(find.text('Create your account'), findsOneWidget);
}

/// Fills the six required items of Screen 1 (date of birth through the
/// controller, as the picker is a Material dialog).
Future<void> _fillScreenOne(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('signup-name')), 'Ada Lovelace');
  await tester.enterText(
    find.byKey(const Key('signup-email')),
    'ada@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('signup-password')),
    'strong-pass1',
  );
  _container(
    tester,
  ).read(signUpProvider.notifier).setDateOfBirth(DateTime(1990, 5, 14));
  await tester.pumpAndSettle();
  await _tap(tester, find.text('Female'));
  await _tap(tester, _switch('Agree to the Terms and Privacy Policy'));
  await _tap(tester, _switch('Agree to health data processing'));
}

void main() {
  testWidgets('asks for an email before signing in', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp(overrides: fakeOverrides(session: null)));
    await tester.pumpAndSettle();

    expect(find.byType(BrandLockup), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);

    await _tap(tester, _signInButton());

    expect(
      find.text('Enter the email address for your account.'),
      findsOneWidget,
    );
    expect(find.byType(FloatingNav), findsNothing);
  });

  testWidgets('toggles to create account and back', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp(overrides: fakeOverrides(session: null)));
    await tester.pumpAndSettle();

    await _openCreateAccount(tester);
    expect(find.text('Step 1 of 3 · Takes about 90 seconds.'), findsOneWidget);
    expect(_createButton(), findsOneWidget);
    expect(find.text('Already have an account? Sign in'), findsOneWidget);
    // Google sign-in belongs to the sign-in mode only.
    expect(find.text('Continue with Google'), findsNothing);

    await _tap(tester, find.text('Already have an account? Sign in'));
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('successful sign-in calls the gateway and shows the shell', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp(overrides: fakeOverrides(session: null)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'test@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'secret123',
    );
    await _tap(tester, _signInButton());

    expect(find.byType(SignInScreen), findsNothing);
    expect(find.byType(FloatingNav), findsOneWidget);
  });

  testWidgets('a rejected sign-in shows a safe inline error', (tester) async {
    await usePhone(tester);
    final _RejectingGateway gateway = _RejectingGateway();
    await tester.pumpWidget(
      testApp(
        overrides: [
          ...fakeOverrides(session: null),
          authGatewayProvider.overrideWithValue(gateway),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'test@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'wrongpass',
    );
    await _tap(tester, _signInButton());

    expect(gateway.signInCalls, 1);
    expect(
      find.text(
        'That email or password is incorrect. Nothing has changed on your '
        'account.',
      ),
      findsOneWidget,
    );
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('short password is rejected before calling the gateway', (
    tester,
  ) async {
    await usePhone(tester);
    final _RejectingGateway gateway = _RejectingGateway();
    await tester.pumpWidget(
      testApp(
        overrides: [
          ...fakeOverrides(session: null),
          authGatewayProvider.overrideWithValue(gateway),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'test@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      '123',
    );
    await _tap(tester, _signInButton());

    expect(gateway.signInCalls, 0);
    expect(
      find.text('Use at least 6 characters for your password.'),
      findsOneWidget,
    );
  });

  testWidgets('explains setup when sign-in is not configured', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(
      testApp(
        overrides: fakeOverrides(
          session: null,
          gateway: FakeAuthGateway(configured: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Setup needed'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsNothing);
  });

  group('Create account (Screen 1)', () {
    testWidgets('the CTA stays disabled until all six items are valid', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(testApp(overrides: fakeOverrides(session: null)));
      await tester.pumpAndSettle();
      await _openCreateAccount(tester);

      expect(_enabled(tester, _createButton()), isFalse);
      expect(
        find.text('Fill in every field and turn on both switches to continue.'),
        findsOneWidget,
      );
      // Consent switches are never pre-ticked.
      for (final label in const [
        'Agree to the Terms and Privacy Policy',
        'Agree to health data processing',
      ]) {
        await _reveal(tester, _switch(label));
        expect(tester.widget<AppSwitch>(_switch(label)).value, isFalse);
      }
      expect(find.text(kTermsConsentText), findsOneWidget);
      expect(find.text(kHealthConsentText), findsOneWidget);
      expect(find.text('Terms'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);

      await _fillScreenOne(tester);
      await _reveal(tester, _createButton());
      expect(_enabled(tester, _createButton()), isTrue);

      // Turning a consent off disables it again.
      await _tap(tester, _switch('Agree to health data processing'));
      await _reveal(tester, _createButton());
      expect(_enabled(tester, _createButton()), isFalse);
    });

    testWidgets('name must be 2–60 characters; password rules show as checks', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(testApp(overrides: fakeOverrides(session: null)));
      await tester.pumpAndSettle();
      await _openCreateAccount(tester);

      await tester.enterText(find.byKey(const Key('signup-name')), 'A');
      await tester.pumpAndSettle();
      expect(
        find.text('Use a name between 2 and 60 characters.'),
        findsOneWidget,
      );

      expect(
        find.bySemanticsLabel('8 or more characters: not yet'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('signup-password')),
        'abcdefgh',
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('8 or more characters: done'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('At least one letter: done'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('At least one number: not yet'),
        findsOneWidget,
      );

      // Show / hide password is labelled.
      expect(find.byTooltip('Show password'), findsOneWidget);
      await _tap(tester, find.byTooltip('Show password'));
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('under 18 shows the adults-only message and stores nothing', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(testApp(overrides: fakeOverrides(session: null)));
      await tester.pumpAndSettle();
      await _openCreateAccount(tester);

      final DateTime now = DateTime.now();
      final SignUpController controller = _container(
        tester,
      ).read(signUpProvider.notifier);
      controller.setDateOfBirth(DateTime(now.year - 17, now.month, now.day));
      await tester.pumpAndSettle();

      await _reveal(tester, find.text(kUnderAgeMessage));
      expect(find.text(kUnderAgeMessage), findsOneWidget);
      expect(_container(tester).read(signUpProvider).dateOfBirth, isNull);

      // A valid date clears it.
      controller.setDateOfBirth(DateTime(1990, 5, 14));
      await tester.pumpAndSettle();
      expect(find.text(kUnderAgeMessage), findsNothing);
      expect(find.text('14 May 1990'), findsOneWidget);
    });

    testWidgets('the date field opens a typed date picker', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(testApp(overrides: fakeOverrides(session: null)));
      await tester.pumpAndSettle();
      await _openCreateAccount(tester);

      await _tap(tester, find.byKey(const Key('signup-dob')));
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byType(TextField),
        ),
        '05/14/1990',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.text('14 May 1990'), findsOneWidget);
    });

    testWidgets(
      'sign-up goes through the code step, then onboarding saves Screen 1',
      (tester) async {
        await usePhone(tester);
        final FakeAuthGateway gateway = FakeAuthGateway(session: null);
        final FakeProfileRepository profiles = FakeProfileRepository(
          latency: Duration.zero,
          seed: kFreshProfile,
        );
        await tester.pumpWidget(
          testApp(
            overrides: fakeOverrides(
              session: null,
              gateway: gateway,
              profileRepository: profiles,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _openCreateAccount(tester);
        await _fillScreenOne(tester);

        await _tap(tester, _createButton());
        expect(gateway.signUpCalls, 1);
        expect(gateway.lastSignUpEmail, 'ada@example.com');
        expect(find.text('Confirm your email'), findsOneWidget);
        expect(find.text('We sent a code to ada@example.com'), findsOneWidget);
        // Nothing saved yet: there is no session.
        expect(profiles.savedBodies, isEmpty);

        // Wrong code: safe error, details kept.
        await tester.enterText(find.byKey(const Key('signup-code')), '000000');
        await _tap(tester, find.widgetWithText(FilledButton, 'Confirm code'));
        expect(gateway.verifyCalls, 1);
        expect(
          find.text(
            'That code didn’t work. Check the email and try again. Your '
            'details are still here.',
          ),
          findsOneWidget,
        );

        await _tap(tester, find.text('Send a new code'));
        expect(gateway.resendCalls, 1);
        expect(
          find.text('We sent a new code to ada@example.com.'),
          findsOneWidget,
        );

        await tester.enterText(find.byKey(const Key('signup-code')), '123456');
        await _tap(tester, find.widgetWithText(FilledButton, 'Confirm code'));

        // Session exists → shell gate → onboarding at Screen 2.
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.text('Your health basics'), findsOneWidget);
        expect(find.textContaining('Step 2 of 3'), findsOneWidget);

        // Screen 1 reached /profile as a partial update.
        expect(profiles.savedBodies, hasLength(1));
        expect(profiles.savedBodies.single, <String, dynamic>{
          'name': 'Ada Lovelace',
          'date_of_birth': '1990-05-14',
          'sex_at_birth': 'female',
          'consent': <String, dynamic>{'terms': true, 'health_data': true},
        });
        expect(profiles.current.onboardingComplete, isTrue);
        expect(profiles.current.consent?.version, kConsentVersion);
        // The answers are no longer held by the sign-up provider.
        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(OnboardingScreen)),
        );
        expect(container.read(signUpProvider).name, isEmpty);
        expect(container.read(signUpHandoffProvider), isNull);
      },
    );

    testWidgets('a project without email confirmation signs straight in', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(
        testApp(
          overrides: fakeOverrides(
            session: null,
            profile: kFreshProfile,
            gateway: FakeAuthGateway(session: null, confirmEmail: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openCreateAccount(tester);
      await _fillScreenOne(tester);
      await _tap(tester, _createButton());

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Your health basics'), findsOneWidget);
    });

    testWidgets('fits a 320 dp screen at 200 % text scale without overflow', (
      tester,
    ) async {
      await usePhone(tester, size: const Size(320, 640));
      await tester.pumpWidget(
        testScreen(
          const SignInScreen(),
          overrides: fakeOverrides(session: null),
          size: const Size(320, 640),
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();

      await _tap(tester, find.text('New here? Create an account'));
      await _reveal(tester, _createButton());
      expect(_createButton(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('fits a 320 dp screen at 200 % text scale without overflow', (
    tester,
  ) async {
    await usePhone(tester, size: const Size(320, 640));
    await tester.pumpWidget(
      testScreen(
        const SignInScreen(),
        overrides: fakeOverrides(session: null),
        size: const Size(320, 640),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Continue with Google'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
