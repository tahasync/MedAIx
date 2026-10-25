/// Screens 2–3 of the questionnaire ("Your health basics", "About you"),
/// plus Screen 1 ("Create your account") when the account has no date of
/// birth, sex at birth or consent on file. Shown without the nav, either by
/// the shell gate or at `/onboarding` for the completion state. State lives
/// in [onboardingProvider] so it survives rebuilds.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../../profile/providers/profile_form.dart';
import '../../profile/ui/profile_fields.dart';
import '../providers/onboarding_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  OnboardingController get _notifier => ref.read(onboardingProvider.notifier);

  Future<void> _finish() async {
    final GoRouter router = GoRouter.of(context);
    // The completion state lives at /onboarding, outside the shell gate,
    // which would otherwise swap in the tabs as soon as the profile saves.
    router.go(AppRoutes.onboarding);
    await _notifier.finish();
  }

  Future<void> _skip() async {
    final GoRouter router = GoRouter.of(context);
    final SkipOutcome outcome = await _notifier.skip();
    if (mounted) {
      switch (outcome) {
        case SkipOutcome.saved:
          showToast(context, 'Details saved');
        case SkipOutcome.saveFailed:
          showToast(
            context,
            'Couldn’t save your details. Add them later from Settings.',
          );
        case SkipOutcome.skippedUnsaved:
          break;
      }
    }
    router.go(AppRoutes.home);
  }

  void _leave(String route) {
    GoRouter.of(context).go(route);
    _notifier.reset();
  }

  @override
  Widget build(BuildContext context) {
    final OnboardingState s = ref.watch(onboardingProvider);

    if (s.completed) {
      return AppScaffold(
        body: AppScreen(
          insetForNav: false,
          header: const ScreenHeader(
            title: 'You’re all set',
            subtitle: 'Your profile is saved',
          ),
          children: [
            const ProgressBar(value: 1, semanticLabel: 'Profile complete'),
            const SizedBox(height: AppSpace.xl),
            _CompletionStep(
              onUpload: () => _leave(AppRoutes.upload),
              onSkip: () => _leave(AppRoutes.home),
            ),
          ],
        ),
      );
    }

    final (String title, Widget body) = switch (s.step) {
      OnboardingStep.account => (
        'Create your account',
        const _AccountStep(key: ValueKey('account')),
      ),
      OnboardingStep.health => (
        'Your health basics',
        const _HealthStep(key: ValueKey('health')),
      ),
      OnboardingStep.about => (
        'About you',
        const _AboutStep(key: ValueKey('about')),
      ),
    };
    final String stepLabel =
        'Step ${s.screenNumber} of ${OnboardingState.screenCount}';
    final bool accountGate =
        s.step == OnboardingStep.account && !s.accountValid;

    return AppScaffold(
      body: AppScreen(
        insetForNav: false,
        header: ScreenHeader(
          title: title,
          subtitle: switch (s.step) {
            OnboardingStep.account => '$stepLabel · Required',
            OnboardingStep.health => '$stepLabel · All optional, one tap each',
            OnboardingStep.about => '$stepLabel · Optional',
          },
        ),
        children: [
          ProgressBar(value: s.progress, semanticLabel: stepLabel),
          if (s.accountSaveError != null) ...[
            const SizedBox(height: AppSpace.xl),
            ErrorCard(
              title: 'Couldn’t save your account details',
              message: s.accountSaveError!,
              dataSafety:
                  'Your account was created and your answers are kept here '
                  'until they save.',
              onPrimary: s.accountSaving ? null : _notifier.saveAccountDraft,
            ),
          ],
          StateSwitcher(child: body),
          if (s.saveError != null) ...[
            const SizedBox(height: AppSpace.xl),
            ErrorCard(
              title: 'Couldn’t save your details',
              message: s.saveError!,
              dataSafety: 'Your answers are still here.',
              onPrimary: s.saving ? null : _finish,
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          if (s.isLast)
            PrimaryButton(
              label: 'Finish',
              loading: s.saving,
              onPressed: s.saving ? null : _finish,
            )
          else
            PrimaryButton(
              label: 'Continue',
              onPressed: s.saving || accountGate ? null : _notifier.next,
            ),
          if (accountGate) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              'Fill in every field and turn on both switches to continue.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.colors.muted),
            ),
          ],
          const SizedBox(height: AppSpace.xs),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!s.isFirst)
                LinkButton(
                  label: 'Back',
                  onPressed: s.saving ? null : _notifier.back,
                ),
              // Screen 1 is required; Screens 2–3 can always be skipped.
              if (s.step != OnboardingStep.account)
                LinkButton(
                  label: 'Skip for now',
                  onPressed: s.saving ? null : _skip,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 1 · Create your account (Google sign-in / older accounts only)
// ---------------------------------------------------------------------------

class _AccountStep extends ConsumerStatefulWidget {
  const _AccountStep({super.key});

  @override
  ConsumerState<_AccountStep> createState() => _AccountStepState();
}

class _AccountStepState extends ConsumerState<_AccountStep> {
  late final TextEditingController _name = TextEditingController(
    text: ref.read(onboardingProvider).name,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OnboardingState s = ref.watch(onboardingProvider);
    final OnboardingController n = ref.read(onboardingProvider.notifier);
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'A few details so MedAIx can read your reports with the right '
          'ranges. Your email stays as it is.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: c.muted),
        ),
        const SizedBox(height: AppSpace.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('onboarding-name'),
                controller: _name,
                enabled: !s.saving,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: ProfileValidation.name,
                onChanged: n.setName,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(LucideIcons.user),
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              DateOfBirthField(
                key: const Key('onboarding-dob'),
                value: s.dateOfBirth,
                enabled: !s.saving,
                errorText: s.dateOfBirthError,
                onChanged: n.setDateOfBirth,
              ),
              SexAtBirthField(
                value: s.sexAtBirth,
                enabled: !s.saving,
                onChanged: n.setSexAtBirth,
              ),
              const SectionTitle('Consent'),
              ConsentSwitches(
                terms: s.terms,
                healthData: s.healthData,
                enabled: !s.saving,
                onTermsChanged: n.setTerms,
                onHealthDataChanged: n.setHealthData,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 2 · Your health basics
// ---------------------------------------------------------------------------

class _HealthStep extends ConsumerWidget {
  const _HealthStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OnboardingState s = ref.watch(onboardingProvider);
    final OnboardingController n = ref.read(onboardingProvider.notifier);
    final bool enabled = !s.saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const QuestionTitle(
          'Any ongoing conditions?',
          helper: 'Chooses which values and trends to highlight.',
          first: true,
        ),
        MultiChoiceChips(
          options: kConditionOptions,
          selected: s.conditions,
          enabled: enabled,
          onChanged: n.setConditions,
        ),
        const QuestionTitle(
          'Any allergies?',
          helper: 'Used for medicine safety alerts.',
        ),
        MultiChoiceChips(
          options: kAllergyOptions,
          selected: s.allergies,
          enabled: enabled,
          onChanged: n.setAllergies,
        ),
        MedicinesQuestion(
          fieldKey: const Key('onboarding-medicines'),
          takesMedicines: s.takesMedicines,
          names: s.medicines,
          enabled: enabled,
          onTakesMedicinesChanged: n.setTakesMedicines,
          onNamesChanged: n.setMedicines,
        ),
        GenderFilterQuestion(
          sexAtBirth: s.sexAtBirth,
          age: s.age,
          pregnancyStatus: s.pregnancyStatus,
          prostateUrinaryIssue: s.prostateUrinaryIssue,
          enabled: enabled,
          onPregnancyChanged: n.setPregnancyStatus,
          onProstateChanged: n.setProstateUrinaryIssue,
        ),
        const SizedBox(height: AppSpace.xl),
        Text(
          'Camera and notification access are only requested when you first '
          'need them.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.colors.muted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 3 · About you
// ---------------------------------------------------------------------------

class _AboutStep extends ConsumerWidget {
  const _AboutStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OnboardingState s = ref.watch(onboardingProvider);
    final OnboardingController n = ref.read(onboardingProvider.notifier);
    final bool enabled = !s.saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const QuestionTitle(
          'What would you like help with first?',
          helper: 'Sets the first thing the Home screen shows.',
          first: true,
        ),
        GoalChoice(
          value: s.firstGoal,
          enabled: enabled,
          onChanged: n.setFirstGoal,
        ),
        const QuestionTitle(
          'Height and weight',
          helper: 'For BMI and goals. Leave empty to skip.',
        ),
        UnitToggle(unit: s.unit, enabled: enabled, onChanged: n.setUnit),
        const SizedBox(height: AppSpace.lg),
        HeightWeightFields(
          heightKey: const Key('onboarding-height'),
          weightKey: const Key('onboarding-weight'),
          heightCm: s.heightCm,
          weightKg: s.weightKg,
          unit: s.unit,
          enabled: enabled,
          heightError: s.heightError,
          weightError: s.weightError,
          onHeightChanged: n.setHeightCm,
          onWeightChanged: n.setWeightKg,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Completion
// ---------------------------------------------------------------------------

class _CompletionStep extends StatelessWidget {
  const _CompletionStep({required this.onUpload, required this.onSkip});

  final VoidCallback onUpload;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: LucideIcons.circleCheck,
      title: 'Your account is ready',
      reason:
          'Upload a lab report and MedAIx will explain it in plain language. '
          'You can change any answer later in Settings › Profile.',
      action: PrimaryButton(
        label: 'Upload your first report',
        icon: LucideIcons.upload,
        onPressed: onUpload,
      ),
      secondaryAction: GhostButton(label: 'Skip for now', onPressed: onSkip),
    );
  }
}
