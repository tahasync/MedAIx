/// Onboarding state for Screens 2–3 of the questionnaire (and Screen 1 when
/// the account came from Google or predates the questionnaire), kept in a
/// Notifier so it survives rebuilds, theme changes and the shell swapping
/// screens.
///
/// After an email sign-up the Screen 1 answers arrive through
/// [signUpHandoffProvider]; this controller writes them to `/profile` first
/// and then collects the optional health answers.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/sign_up_providers.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/providers/profile_form.dart';
import '../../profile/providers/profile_providers.dart';
import '../../reports/data/reports_repository.dart';
import '../../settings/providers/settings_providers.dart';
import 'onboarding_state.dart';

export 'onboarding_state.dart';

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() {
    // A different account starts onboarding fresh (a token refresh does not).
    ref.watch(authControllerProvider.select((s) => s?.userId));
    final ProfileDraft? handoff = ref.read(signUpHandoffProvider);
    final PatientProfile? profile = ref.read(profileProvider).valueOrNull;
    if (handoff != null) {
      // Write Screen 1 to /profile as soon as the session is in place.
      unawaited(Future<void>.microtask(saveAccountDraft));
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
    } on Object catch (_) {
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
    } on Object catch (_) {
      return 'Could not save your details.';
    }
  }
}

final onboardingProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );
