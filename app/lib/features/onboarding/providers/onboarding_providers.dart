/// Onboarding state for Screens 2–3 of the questionnaire (and Screen 1 when
/// the account came from Google or predates the questionnaire), kept in a
/// Notifier so it survives rebuilds, theme changes and the shell swapping
/// screens.
///
/// After an email sign-up the Screen 1 answers arrive through
/// [signUpHandoffProvider]; this controller writes them to `/profile` first
/// and then collects the optional health answers.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/sign_up_providers.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/providers/profile_form.dart';
import '../../profile/providers/profile_providers.dart';
import '../../reports/data/reports_repository.dart';
import '../../settings/providers/settings_providers.dart';

/// Result of "Skip for now".
enum SkipOutcome {
  /// Something was answered and saved.
  saved,

  /// Nothing to save; only marked as seen.
  skippedUnsaved,

  /// Answers were valid but the save failed; marked as seen anyway.
  saveFailed,
}

/// The questionnaire screens this run of onboarding shows.
enum OnboardingStep {
  /// Screen 1 — only when the account has no date of birth, sex at birth or
  /// consent on file (Google sign-in, older accounts).
  account,

  /// Screen 2 — your health basics.
  health,

  /// Screen 3 — about you.
  about,
}

@immutable
class OnboardingState {
  const OnboardingState({
    this.includesAccountStep = true,
    this.index = 0,
    this.name = '',
    this.dateOfBirth,
    this.dateOfBirthError,
    this.legacyAge,
    this.sexAtBirth,
    this.terms = false,
    this.healthData = false,
    this.pendingAccountDraft,
    this.accountSaving = false,
    this.accountSaveError,
    this.conditions = const <String>{},
    this.allergies = const <String>{},
    this.takesMedicines,
    this.medicines = '',
    this.pregnancyStatus,
    this.prostateUrinaryIssue,
    this.firstGoal,
    this.heightCm,
    this.weightKg,
    this.unit = UnitSystem.metric,
    this.saving = false,
    this.saveError,
    this.completed = false,
  });

  /// Seeds from the sign-up hand-off (preferred) or the stored profile.
  factory OnboardingState.initial({
    ProfileDraft? handoff,
    PatientProfile? profile,
  }) {
    final bool hasBasics = profile?.hasAccountBasics ?? false;
    return OnboardingState(
      includesAccountStep: handoff == null && !hasBasics,
      name: handoff?.name ?? profile?.name ?? '',
      dateOfBirth: handoff?.dateOfBirth ?? profile?.dateOfBirth,
      legacyAge: profile?.age,
      sexAtBirth: handoff?.sexAtBirth ?? profile?.sexAtBirth,
      pendingAccountDraft: handoff,
      conditions: profile?.conditionList.toSet() ?? const <String>{},
      allergies: profile?.allergyList.toSet() ?? const <String>{},
      takesMedicines: profile?.takesMedicines,
      medicines: profile?.medicationList.join('\n') ?? '',
      pregnancyStatus: profile?.pregnancyStatus,
      prostateUrinaryIssue: profile?.prostateUrinaryIssue,
      firstGoal: profile?.firstGoal,
      heightCm: profile?.heightCm,
      weightKg: profile?.weightKg,
    );
  }

  /// Screens in the questionnaire.
  static const int screenCount = 3;

  final bool includesAccountStep;

  /// 0-based position in [steps].
  final int index;

  // ---- Screen 1 ----
  final String name;

  /// Only ever a valid (18+) date.
  final DateTime? dateOfBirth;
  final String? dateOfBirthError;

  /// The server's age when the profile has no date of birth (older data).
  final int? legacyAge;
  final String? sexAtBirth;
  final bool terms;
  final bool healthData;

  /// Screen 1 answers from the sign-up form, until they reach `/profile`.
  final ProfileDraft? pendingAccountDraft;
  final bool accountSaving;
  final String? accountSaveError;

  // ---- Screen 2 ----
  final Set<String> conditions;
  final Set<String> allergies;
  final bool? takesMedicines;
  final String medicines;
  final String? pregnancyStatus;
  final String? prostateUrinaryIssue;

  // ---- Screen 3 ----
  final String? firstGoal;

  /// Canonical values; NaN means the field holds something that is not a
  /// number.
  final double? heightCm;
  final double? weightKg;
  final UnitSystem unit;

  // ---- Status ----
  final bool saving;
  final String? saveError;

  /// Everything saved: show "Upload your first report" / "Skip for now".
  final bool completed;

  List<OnboardingStep> get steps => <OnboardingStep>[
    if (includesAccountStep) OnboardingStep.account,
    OnboardingStep.health,
    OnboardingStep.about,
  ];

  OnboardingStep get step => steps[index.clamp(0, steps.length - 1)];
  bool get isFirst => index == 0;
  bool get isLast => index == steps.length - 1;

  /// Questionnaire screen number (1–3), so the header reads "Step 2 of 3"
  /// right after the sign-up screen.
  int get screenNumber => switch (step) {
    OnboardingStep.account => 1,
    OnboardingStep.health => 2,
    OnboardingStep.about => 3,
  };

  double get progress => completed ? 1 : screenNumber / screenCount;

  int? get age =>
      dateOfBirth == null ? legacyAge : PatientProfile.ageAt(dateOfBirth!);

  bool get accountValid =>
      ProfileValidation.name(name) == null &&
      dateOfBirth != null &&
      ProfileValidation.sex(sexAtBirth) == null &&
      terms &&
      healthData;

  String? get heightError => ProfileValidation.heightCm(heightCm);
  String? get weightError => ProfileValidation.weightKg(weightKg);
  bool get aboutValid => heightError == null && weightError == null;

  List<String> get medicineList => splitNames(medicines);

  /// Screen 1 as typed on the account step (not the hand-off).
  ProfileDraft get accountDraft => ProfileDraft(
    name: name.trim(),
    dateOfBirth: dateOfBirth,
    sexAtBirth: sexAtBirth,
    grantConsent: terms && healthData,
  );

  /// Screen 2: only what was answered.
  ProfileDraft get healthDraft => ProfileDraft(
    conditions: conditions.isEmpty ? null : PatientProfile.join(conditions),
    allergies: allergies.isEmpty ? null : PatientProfile.join(allergies),
    takesMedicines: takesMedicines,
    medications: takesMedicines == null
        ? null
        : takesMedicines!
        ? PatientProfile.join(medicineList)
        : '',
    pregnancyStatus: pregnancyStatus,
    prostateUrinaryIssue: prostateUrinaryIssue,
  );

  /// Screen 3: only what was answered and is a number.
  ProfileDraft get aboutDraft => ProfileDraft(
    firstGoal: firstGoal,
    heightCm: heightCm != null && !heightCm!.isNaN ? heightCm : null,
    weightKg: weightKg != null && !weightKg!.isNaN ? weightKg : null,
  );

  OnboardingState copyWith({
    bool? includesAccountStep,
    int? index,
    String? name,
    DateTime? dateOfBirth,
    bool clearDateOfBirth = false,
    String? dateOfBirthError,
    bool clearDateOfBirthError = false,
    String? sexAtBirth,
    bool? terms,
    bool? healthData,
    ProfileDraft? pendingAccountDraft,
    bool clearPendingAccountDraft = false,
    bool? accountSaving,
    String? accountSaveError,
    bool clearAccountSaveError = false,
    Set<String>? conditions,
    Set<String>? allergies,
    bool? takesMedicines,
    String? medicines,
    String? pregnancyStatus,
    bool clearPregnancyStatus = false,
    String? prostateUrinaryIssue,
    bool clearProstateUrinaryIssue = false,
    String? firstGoal,
    double? heightCm,
    bool clearHeight = false,
    double? weightKg,
    bool clearWeight = false,
    UnitSystem? unit,
    bool? saving,
    String? saveError,
    bool clearSaveError = false,
    bool? completed,
  }) {
    return OnboardingState(
      includesAccountStep: includesAccountStep ?? this.includesAccountStep,
      index: index ?? this.index,
      name: name ?? this.name,
      dateOfBirth: clearDateOfBirth ? null : (dateOfBirth ?? this.dateOfBirth),
      dateOfBirthError: clearDateOfBirthError
          ? null
          : (dateOfBirthError ?? this.dateOfBirthError),
      legacyAge: legacyAge,
      sexAtBirth: sexAtBirth ?? this.sexAtBirth,
      terms: terms ?? this.terms,
      healthData: healthData ?? this.healthData,
      pendingAccountDraft: clearPendingAccountDraft
          ? null
          : (pendingAccountDraft ?? this.pendingAccountDraft),
      accountSaving: accountSaving ?? this.accountSaving,
      accountSaveError: clearAccountSaveError
          ? null
          : (accountSaveError ?? this.accountSaveError),
      conditions: conditions ?? this.conditions,
      allergies: allergies ?? this.allergies,
      takesMedicines: takesMedicines ?? this.takesMedicines,
      medicines: medicines ?? this.medicines,
      pregnancyStatus: clearPregnancyStatus
          ? null
          : (pregnancyStatus ?? this.pregnancyStatus),
      prostateUrinaryIssue: clearProstateUrinaryIssue
          ? null
          : (prostateUrinaryIssue ?? this.prostateUrinaryIssue),
      firstGoal: firstGoal ?? this.firstGoal,
      heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
      weightKg: clearWeight ? null : (weightKg ?? this.weightKg),
      unit: unit ?? this.unit,
      saving: saving ?? this.saving,
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
      completed: completed ?? this.completed,
    );
  }
}

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() {
    // A different account starts onboarding fresh (a token refresh does not).
    ref.watch(authControllerProvider.select((s) => s?.userId));
    final ProfileDraft? handoff = ref.read(signUpHandoffProvider);
    final PatientProfile? profile = ref.read(profileProvider).valueOrNull;
    if (handoff != null) {
      // Write Screen 1 to /profile as soon as the session is in place.
      Future<void>.microtask(saveAccountDraft);
    }
    return OnboardingState.initial(handoff: handoff, profile: profile);
  }

  void reset() => state = OnboardingState.initial(
    profile: ref.read(profileProvider).valueOrNull,
  );

  // ---- Screen 1 ----

  void setName(String value) => state = state.copyWith(name: value);

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

  /// The gender-filtered answer belongs to one group only, so switching
  /// group drops the other group's answer.
  void setSexAtBirth(String value) => state = state.copyWith(
    sexAtBirth: value,
    clearPregnancyStatus: value != 'female',
    clearProstateUrinaryIssue: value != 'male',
  );

  void setTerms(bool value) => state = state.copyWith(terms: value);

  void setHealthData(bool value) => state = state.copyWith(healthData: value);

  /// Sends the sign-up answers to `/profile`. Safe to call again after a
  /// failure; a no-op once saved.
  Future<void> saveAccountDraft() async {
    final ProfileDraft? draft = state.pendingAccountDraft;
    if (draft == null || state.accountSaving) return;
    state = state.copyWith(accountSaving: true, clearAccountSaveError: true);
    try {
      // Straight to the repository: refreshing [profileProvider] here would
      // let the shell gate close onboarding before Screens 2–3 are shown.
      await ref.read(profileRepositoryProvider).save(draft);
      ref.read(signUpHandoffProvider.notifier).clear();
      state = state.copyWith(
        accountSaving: false,
        clearPendingAccountDraft: true,
      );
    } on RepositoryException catch (error) {
      state = state.copyWith(
        accountSaving: false,
        accountSaveError: error.message,
      );
    } catch (_) {
      state = state.copyWith(
        accountSaving: false,
        accountSaveError: 'Could not save your account details.',
      );
    }
  }

  // ---- Screen 2 ----

  void setConditions(Set<String> value) =>
      state = state.copyWith(conditions: value);

  void toggleCondition(String label) =>
      setConditions(toggleExclusive(state.conditions, label));

  void setAllergies(Set<String> value) =>
      state = state.copyWith(allergies: value);

  void toggleAllergy(String label) =>
      setAllergies(toggleExclusive(state.allergies, label));

  void setTakesMedicines(bool value) =>
      state = state.copyWith(takesMedicines: value);

  void setMedicines(String value) => state = state.copyWith(medicines: value);

  void setPregnancyStatus(String value) =>
      state = state.copyWith(pregnancyStatus: value);

  void setProstateUrinaryIssue(String value) =>
      state = state.copyWith(prostateUrinaryIssue: value);

  // ---- Screen 3 ----

  void setFirstGoal(String value) => state = state.copyWith(firstGoal: value);

  void setHeightCm(double? value) => state = value == null
      ? state.copyWith(clearHeight: true)
      : state.copyWith(heightCm: value);

  void setWeightKg(double? value) => state = value == null
      ? state.copyWith(clearWeight: true)
      : state.copyWith(weightKg: value);

  void setUnit(UnitSystem value) => state = state.copyWith(unit: value);

  // ---- Navigation ----

  void next() {
    if (state.isLast) return;
    if (state.step == OnboardingStep.account && !state.accountValid) return;
    state = state.copyWith(index: state.index + 1, clearSaveError: true);
  }

  void back() {
    if (state.isFirst) return;
    state = state.copyWith(index: state.index - 1, clearSaveError: true);
  }

  void dismissError() => state = state.copyWith(clearSaveError: true);

  // ---- Saving ----

  /// Everything answered so far, plus Screen 1 if it has not reached the
  /// server yet. Empty when nothing was answered.
  ProfileDraft _draft({required bool includeAbout}) {
    ProfileDraft draft = const ProfileDraft();
    if (state.pendingAccountDraft != null) {
      draft = draft.merge(state.pendingAccountDraft!);
    }
    if (state.includesAccountStep && state.accountValid) {
      draft = draft.merge(state.accountDraft);
    }
    draft = draft.merge(state.healthDraft);
    if (includeAbout) draft = draft.merge(state.aboutDraft);
    return draft;
  }

  /// "Finish": saves the whole questionnaire and marks onboarding as seen.
  /// False (with [OnboardingState.saveError] set) when it could not save.
  Future<bool> finish() async {
    if (state.includesAccountStep && !state.accountValid) {
      state = state.copyWith(
        saveError: 'Go back and complete your account details first.',
      );
      return false;
    }
    if (!state.aboutValid) {
      state = state.copyWith(saveError: 'Check your height and weight.');
      return false;
    }
    state = state.copyWith(saving: true, clearSaveError: true);
    final ProfileDraft draft = _draft(includeAbout: true);
    final String? error = draft.isEmpty ? null : await _save(draft);
    if (error != null) {
      state = state.copyWith(saving: false, saveError: error);
      return false;
    }
    ref.read(signUpHandoffProvider.notifier).clear();
    await ref.read(onboardingSeenProvider.notifier).markSeen();
    state = state.copyWith(
      saving: false,
      completed: true,
      clearPendingAccountDraft: true,
    );
    return true;
  }

  /// "Skip for now": saves whatever was answered (and the sign-up answers
  /// if still pending), then remembers that onboarding was seen.
  Future<SkipOutcome> skip() async {
    final ProfileDraft draft = _draft(includeAbout: state.aboutValid);
    SkipOutcome outcome = SkipOutcome.skippedUnsaved;
    if (!draft.isEmpty) {
      state = state.copyWith(saving: true, clearSaveError: true);
      final String? error = await _save(draft);
      outcome = error == null ? SkipOutcome.saved : SkipOutcome.saveFailed;
    }
    if (outcome != SkipOutcome.saveFailed) {
      ref.read(signUpHandoffProvider.notifier).clear();
    }
    await ref.read(onboardingSeenProvider.notifier).markSeen();
    reset();
    return outcome;
  }

  Future<String?> _save(ProfileDraft draft) async {
    try {
      final PatientProfile? saved = await ref
          .read(profileEditorProvider.notifier)
          .save(draft);
      if (saved != null) return null;
      final Object? error = ref.read(profileEditorProvider).error;
      return error is RepositoryException
          ? error.message
          : 'Could not save your details.';
    } catch (_) {
      return 'Could not save your details.';
    }
  }
}

final onboardingProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );
