/// Shared test harness: a fully faked app (auth, repositories, settings,
/// connectivity, update check) so widget tests never touch the network.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tahasync_medaix/core/connectivity.dart';
import 'package:tahasync_medaix/core/features.dart';
import 'package:tahasync_medaix/core/router.dart';
import 'package:tahasync_medaix/core/update_checker.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/data/repositories.dart';
import 'package:tahasync_medaix/features/auth/data/auth_gateway.dart';
import 'package:tahasync_medaix/features/auth/providers/auth_providers.dart';
import 'package:tahasync_medaix/features/profile/data/profile_repository.dart';
import 'package:tahasync_medaix/main.dart';
import 'package:tahasync_medaix/theme/app_theme.dart';

class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({
    this.session,
    this.configured = true,
    this.confirmEmail = true,
    this.validCode = '123456',
  });

  AuthSession? session;
  final bool configured;

  /// Whether sign-up asks for the 6-digit code (as the hosted project does)
  /// or signs the user straight in.
  final bool confirmEmail;

  /// The code [verifyEmailCode] accepts.
  final String validCode;

  int signUpCalls = 0;
  int verifyCalls = 0;
  int resendCalls = 0;
  String? lastSignUpEmail;
  String? lastSignUpPassword;
  final StreamController<AuthSession?> _changes =
      StreamController<AuthSession?>.broadcast();

  /// Simulate a sign-in / sign-out from outside the widget tree.
  void emit(AuthSession? next) {
    session = next;
    _changes.add(next);
  }

  @override
  bool get isConfigured => configured;

  @override
  AuthSession? get currentSession => session;

  @override
  Stream<AuthSession?> get authStateChanges => _changes.stream;

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    emit(kTestSession);
    return const AuthResult();
  }

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
  }) async {
    signUpCalls++;
    lastSignUpEmail = email;
    lastSignUpPassword = password;
    if (confirmEmail) return const AuthResult(needsEmailConfirmation: true);
    emit(kTestSession);
    return const AuthResult();
  }

  @override
  Future<AuthResult> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    verifyCalls++;
    if (code != validCode) {
      return const AuthResult(
        message: 'That code didn’t work. Check the email and try again.',
      );
    }
    emit(kTestSession);
    return const AuthResult();
  }

  @override
  Future<AuthResult> resendEmailCode({required String email}) async {
    resendCalls++;
    return const AuthResult(needsEmailConfirmation: true);
  }

  @override
  Future<AuthResult> signInWithGoogle() async => const AuthResult();

  @override
  Future<void> signOut() async => emit(null);
}

const AuthSession kTestSession = AuthSession(
  userId: 'user-1',
  accessToken: 'token',
  email: 'test@example.com',
);

/// Date of birth that makes the test patient 30 years old today.
final DateTime kTestDateOfBirth = () {
  final DateTime now = DateTime.now();
  return DateTime(now.year - 30, now.month, now.day);
}();

const ProfileConsent kTestConsent = ProfileConsent(
  terms: true,
  healthData: true,
  version: kConsentVersion,
  acceptedAt: null,
);

/// A fully onboarded test patient (female, 30, every answer given).
final PatientProfile kCompleteProfile = PatientProfile(
  id: 1,
  name: 'Test',
  email: 'test@example.com',
  dateOfBirth: kTestDateOfBirth,
  age: 30,
  sexAtBirth: 'female',
  consent: kTestConsent,
  conditions: 'Diabetes',
  allergies: 'Peanuts',
  takesMedicines: true,
  medications: 'Metformin 500 mg',
  pregnancyStatus: 'no',
  firstGoal: 'reports',
  heightCm: 170,
  weightKg: 70,
  onboardingComplete: true,
);

/// Nothing on file yet: onboarding starts at Screen 1 (account basics).
const PatientProfile kFreshProfile = PatientProfile(id: 1);

/// Screen 1 done (as after an email sign-up), Screens 2–3 not yet.
PatientProfile accountOnlyProfile({
  String sexAtBirth = 'female',
  int age = 30,
}) {
  final DateTime now = DateTime.now();
  return PatientProfile(
    id: 1,
    name: 'Ada',
    email: 'test@example.com',
    dateOfBirth: DateTime(now.year - age, now.month, now.day),
    age: age,
    sexAtBirth: sexAtBirth,
    consent: kTestConsent,
    onboardingComplete: false,
  );
}

/// Zero-latency fakes so `pumpAndSettle` returns promptly.
///
/// [sprint] defaults to every feature on so screen tests can reach any
/// screen; `test/feature_gate_test.dart` covers the real build's gate.
/// [profile] defaults to [kCompleteProfile]; pass [profileRepository] to
/// inspect what the screens saved.
List<Override> fakeOverrides({
  int sprint = kAllSprints,
  AuthSession? session = kTestSession,
  PatientProfile? profile,
  bool offline = false,
  bool onboardingSeen = false,
  FakeAuthGateway? gateway,
  FakeReportsRepository? reports,
  FakeProfileRepository? profileRepository,
  FakeMedsRepository? meds,
  FakeWellnessRepository? wellness,
  FakeShareRepository? share,
  FakeSettingsRepository? settings,
}) {
  const Duration zero = Duration.zero;
  return <Override>[
    featuresProvider.overrideWithValue(FeatureFlags(sprint)),
    authGatewayProvider.overrideWithValue(
      gateway ?? FakeAuthGateway(session: session),
    ),
    isOfflineProvider.overrideWith((ref) => Stream<bool>.value(offline)),
    latestReleaseProvider.overrideWith((ref) async => null),
    reportsRepositoryProvider.overrideWithValue(
      reports ?? FakeReportsRepository(latency: zero, uploadDelay: zero),
    ),
    profileRepositoryProvider.overrideWithValue(
      profileRepository ??
          FakeProfileRepository(
            latency: zero,
            seed: profile ?? kCompleteProfile,
          ),
    ),
    medsRepositoryProvider.overrideWithValue(
      meds ?? FakeMedsRepository(latency: zero),
    ),
    wellnessRepositoryProvider.overrideWithValue(
      wellness ?? FakeWellnessRepository(latency: zero),
    ),
    shareRepositoryProvider.overrideWithValue(
      share ?? FakeShareRepository(latency: zero),
    ),
    doctorRepositoryProvider.overrideWithValue(
      FakeDoctorRepository(latency: zero),
    ),
    insightsRepositoryProvider.overrideWithValue(
      FakeInsightsRepository(latency: zero),
    ),
    settingsRepositoryProvider.overrideWithValue(
      settings ?? FakeSettingsRepository(onboardingSeen: onboardingSeen),
    ),
  ];
}

/// The real app (router, themes, shell) on fakes. Pump, then settle.
Widget testApp({List<Override> overrides = const <Override>[]}) {
  return ProviderScope(
    overrides: <Override>[...fakeOverrides(), ...overrides],
    child: const MedAIxApp(),
  );
}

/// The real app started at [location]. Use for screens deep in a tab.
Widget testAppAt(
  String location, {
  List<Override> overrides = const <Override>[],
}) {
  return ProviderScope(
    overrides: <Override>[...fakeOverrides(), ...overrides],
    child: _RouterApp(initialLocation: location),
  );
}

class _RouterApp extends ConsumerWidget {
  const _RouterApp({required this.initialLocation});

  final String initialLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);
    // Jump after the first frame so redirects (sign-in) still apply.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.go(initialLocation);
    });
    return MaterialApp.router(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}

/// A single screen under the app theme, outside the router. For widget
/// tests that only care about one screen's states.
Widget testScreen(
  Widget child, {
  List<Override> overrides = const <Override>[],
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 844),
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: <Override>[...fakeOverrides(), ...overrides],
    child: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        home: child,
      ),
    ),
  );
}

/// Sets the test surface to a phone size; call at the top of a test.
Future<void> usePhone(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
