/// Screen 1 of the questionnaire ("Create your account"): the answers live
/// here, in memory only, until the Supabase session exists. They are then
/// handed to onboarding, which writes them to `/profile`, and cleared.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/data/profile_repository.dart';
import '../../profile/providers/profile_form.dart';
import '../data/auth_gateway.dart';
import 'auth_providers.dart';

enum SignUpStage {
  /// Name, email, password, date of birth, sex at birth, consents.
  form,

  /// "We sent a code to …": the 6-digit email confirmation.
  code,
}

@immutable
class SignUpState {
  const SignUpState({
    this.stage = SignUpStage.form,
    this.name = '',
    this.email = '',
    this.password = '',
    this.dateOfBirth,
    this.dateOfBirthError,
    this.sexAtBirth,
    this.terms = false,
    this.healthData = false,
    this.code = '',
    this.pending = false,
    this.error,
    this.info,
  });

  static const int codeLength = 6;

  final SignUpStage stage;
  final String name;
  final String email;
  final String password;

  /// Only ever a valid (18+) date; an under-age pick is not stored.
  final DateTime? dateOfBirth;
  final String? dateOfBirthError;
  final String? sexAtBirth;
  final bool terms;
  final bool healthData;
  final String code;
  final bool pending;

  /// Plain-language failure, already safe to show.
  final String? error;

  /// Plain-language confirmation ("We sent a new code…").
  final String? info;

  bool get nameValid => ProfileValidation.name(name) == null;
  bool get emailValid => ProfileValidation.email(email) == null;
  bool get passwordLongEnough => ProfileValidation.passwordLongEnough(password);
  bool get passwordHasLetter => ProfileValidation.passwordHasLetter(password);
  bool get passwordHasNumber => ProfileValidation.passwordHasNumber(password);
  bool get passwordValid => ProfileValidation.password(password) == null;
  bool get dateOfBirthValid => dateOfBirth != null;
  bool get sexValid => ProfileValidation.sex(sexAtBirth) == null;
  bool get consentsValid => terms && healthData;

  /// The six required items of Screen 1.
  bool get canSubmit =>
      nameValid &&
      emailValid &&
      passwordValid &&
      dateOfBirthValid &&
      sexValid &&
      consentsValid;

  bool get canVerify => code.length == codeLength;

  /// What `/profile` needs from this screen once the session exists.
  ProfileDraft toProfileDraft() => ProfileDraft(
    name: name.trim(),
    dateOfBirth: dateOfBirth,
    sexAtBirth: sexAtBirth,
    grantConsent: true,
  );

  SignUpState copyWith({
    SignUpStage? stage,
    String? name,
    String? email,
    String? password,
    DateTime? dateOfBirth,
    bool clearDateOfBirth = false,
    String? dateOfBirthError,
    bool clearDateOfBirthError = false,
    String? sexAtBirth,
    bool? terms,
    bool? healthData,
    String? code,
    bool? pending,
    String? error,
    bool clearError = false,
    String? info,
    bool clearInfo = false,
  }) {
    return SignUpState(
      stage: stage ?? this.stage,
      name: name ?? this.name,
      email: email ?? this.email,
      password: password ?? this.password,
      dateOfBirth: clearDateOfBirth ? null : (dateOfBirth ?? this.dateOfBirth),
      dateOfBirthError: clearDateOfBirthError
          ? null
          : (dateOfBirthError ?? this.dateOfBirthError),
      sexAtBirth: sexAtBirth ?? this.sexAtBirth,
      terms: terms ?? this.terms,
      healthData: healthData ?? this.healthData,
      code: code ?? this.code,
      pending: pending ?? this.pending,
      error: clearError ? null : (error ?? this.error),
      info: clearInfo ? null : (info ?? this.info),
    );
  }
}

class SignUpController extends Notifier<SignUpState> {
  @override
  SignUpState build() => const SignUpState();

  void reset() => state = const SignUpState();

  // ---- Screen 1 fields ----

  void setName(String value) => state = state.copyWith(name: value);

  void setEmail(String value) => state = state.copyWith(email: value.trim());

  void setPassword(String value) => state = state.copyWith(password: value);

  /// 1.4 — under 18 shows the spec's message and stores nothing.
  void setDateOfBirth(DateTime value, {DateTime? today}) {
    final DateTime date = DateTime(value.year, value.month, value.day);
    final String? error = ProfileValidation.dateOfBirth(date, today: today);
    if (error != null) {
      state = state.copyWith(clearDateOfBirth: true, dateOfBirthError: error);
      return;
    }
    state = state.copyWith(dateOfBirth: date, clearDateOfBirthError: true);
  }

  void setSexAtBirth(String value) => state = state.copyWith(sexAtBirth: value);

  void setTerms(bool value) => state = state.copyWith(terms: value);

  void setHealthData(bool value) => state = state.copyWith(healthData: value);

  void setCode(String value) =>
      state = state.copyWith(code: value, clearError: true);

  // ---- Flow ----

  /// Creates the Supabase account. Moves to the code step when the project
  /// confirms emails; otherwise the session exists already and onboarding
  /// takes over.
  Future<void> submit() async {
    if (!state.canSubmit || state.pending) return;
    state = state.copyWith(pending: true, clearError: true, clearInfo: true);
    final AuthResult result = await ref
        .read(authGatewayProvider)
        .signUp(email: state.email, password: state.password);
    if (result.message != null) {
      state = state.copyWith(
        pending: false,
        error: '${result.message} No account was created.',
      );
      return;
    }
    if (result.needsEmailConfirmation) {
      state = state.copyWith(pending: false, stage: SignUpStage.code);
      return;
    }
    _handOff();
  }

  Future<void> verifyCode() async {
    if (!state.canVerify || state.pending) return;
    state = state.copyWith(pending: true, clearError: true, clearInfo: true);
    final AuthResult result = await ref
        .read(authGatewayProvider)
        .verifyEmailCode(email: state.email, code: state.code);
    if (result.message != null) {
      state = state.copyWith(
        pending: false,
        error: '${result.message} Your details are still here.',
      );
      return;
    }
    _handOff();
  }

  Future<void> resendCode() async {
    if (state.pending) return;
    state = state.copyWith(pending: true, clearError: true, clearInfo: true);
    final AuthResult result = await ref
        .read(authGatewayProvider)
        .resendEmailCode(email: state.email);
    state = state.copyWith(
      pending: false,
      error: result.message == null
          ? null
          : '${result.message} Your details are still here.',
      info: result.message == null
          ? 'We sent a new code to ${state.email}.'
          : null,
    );
  }

  /// Back from the code step to fix the email or password.
  void backToForm() => state = state.copyWith(
    stage: SignUpStage.form,
    code: '',
    clearError: true,
    clearInfo: true,
  );

  /// The session exists: pass the Screen 1 answers to onboarding (which
  /// saves them to `/profile`) and forget them here.
  void _handOff() {
    ref.read(signUpHandoffProvider.notifier).set(state.toProfileDraft());
    state = const SignUpState();
  }
}

final signUpProvider = NotifierProvider<SignUpController, SignUpState>(
  SignUpController.new,
);

/// The Screen 1 profile fields waiting to be written to `/profile` after a
/// fresh sign-up. Onboarding picks this up on its first build and clears it
/// once saved. Never persisted.
class SignUpHandoff extends Notifier<ProfileDraft?> {
  @override
  ProfileDraft? build() => null;

  void set(ProfileDraft draft) => state = draft;

  void clear() => state = null;
}

final signUpHandoffProvider = NotifierProvider<SignUpHandoff, ProfileDraft?>(
  SignUpHandoff.new,
);
