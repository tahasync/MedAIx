/// Questionnaire state shared by the onboarding routes and controller.
library;

import 'package:flutter/foundation.dart';

import '../../profile/data/profile_repository.dart';
import '../../profile/providers/profile_form.dart';

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
