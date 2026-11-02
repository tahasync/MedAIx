/// Profile widgets split into read and edit responsibilities.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../data/profile_repository.dart';
import '../providers/profile_form.dart';

/// Displays a patient's saved details and read-only status.
class ProfileReadView extends StatelessWidget {
  const ProfileReadView({
    super.key,
    required this.profile,
    required this.email,
    required this.onEdit,
    required this.onDelete,
  });

  final PatientProfile profile;
  final String? email;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final PatientProfile p = profile;
    String listOrNotSet(List<String> items) =>
        items.isEmpty ? 'Not set' : items.join(', ');
    String orNotSet(String? value) =>
        value == null || value.trim().isEmpty ? 'Not set' : value;

    final String medicines = switch (p.takesMedicines) {
      null => 'Not answered',
      false => 'No',
      true =>
        p.medicationList.isEmpty
            ? 'Yes'
            : 'Yes · ${p.medicationList.join(', ')}',
    };
    final ProfileConsent? consent = p.consent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Account', first: true),
        AppCard(
          child: ListRows(
            rows: [
              ListRow(title: 'Name', trailing: _Value(orNotSet(p.name))),
              ListRow(title: 'Email', trailing: _Value(orNotSet(email))),
              ListRow(
                title: 'Date of birth',
                trailing: _Value(
                  p.dateOfBirth == null
                      ? orNotSet(p.age == null ? null : 'Age ${p.age}')
                      : '${formatLongDate(p.dateOfBirth!)} · ${p.age ?? PatientProfile.ageAt(p.dateOfBirth!)}',
                ),
              ),
              ListRow(
                title: 'Sex at birth',
                trailing: _Value(sexLabel(p.sexAtBirth)),
              ),
            ],
          ),
        ),
        const SectionTitle('Health basics'),
        AppCard(
          child: ListRows(
            rows: [
              ListRow(
                title: 'Conditions',
                trailing: _Value(listOrNotSet(p.conditionList)),
              ),
              ListRow(
                title: 'Allergies',
                trailing: _Value(listOrNotSet(p.allergyList)),
              ),
              ListRow(title: 'Regular medicines', trailing: _Value(medicines)),
              if (p.asksPregnancy)
                ListRow(
                  title: 'Pregnant or breastfeeding',
                  trailing: _Value(
                    optionLabel(kPregnancyOptions, p.pregnancyStatus),
                  ),
                ),
              if (p.asksProstate)
                ListRow(
                  title: 'Prostate or urinary problems',
                  trailing: _Value(
                    optionLabel(kProstateOptions, p.prostateUrinaryIssue),
                  ),
                ),
            ],
          ),
        ),
        const SectionTitle('About you'),
        AppCard(
          child: ListRows(
            rows: [
              ListRow(
                title: 'First health goal',
                trailing: _Value(optionLabel(kGoalOptions, p.firstGoal)),
              ),
              ListRow(
                title: 'Height',
                trailing: _Value(
                  Units.heightLabel(p.heightCm, UnitSystem.metric),
                ),
              ),
              ListRow(
                title: 'Weight',
                trailing: _Value(
                  Units.weightLabel(p.weightKg, UnitSystem.metric),
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('Consent'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListRows(
                rows: [
                  ListRow(
                    title: 'Terms and Privacy Policy',
                    trailing: _ConsentStatus(given: consent?.terms ?? false),
                  ),
                  ListRow(
                    title: 'Health data processing',
                    trailing: _ConsentStatus(
                      given: consent?.healthData ?? false,
                    ),
                  ),
                  ListRow(
                    title: 'Policy version',
                    trailing: _Value(orNotSet(consent?.version)),
                  ),
                  ListRow(
                    title: 'Accepted on',
                    trailing: _Value(
                      consent?.acceptedAt == null
                          ? 'Not set'
                          : formatLongDate(consent!.acceptedAt!.toLocal()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              GhostButton(
                label: 'Delete my health data',
                icon: LucideIcons.trash2,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.cardGap),
        PrimaryButton(label: 'Edit details', onPressed: onEdit),
      ],
    );
  }
}

/// Muted, right-aligned row value. [ListRow] already caps the width of
/// `trailing`, so the text wraps to two lines instead of overflowing.
class _Value extends StatelessWidget {
  const _Value(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.end,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.colors.muted),
    );
  }
}

class _ConsentStatus extends StatelessWidget {
  const _ConsentStatus({required this.given});

  final bool given;

  @override
  Widget build(BuildContext context) {
    return StatusLabel(
      status: given ? ValueStatus.ok : ValueStatus.neutral,
      text: given ? 'Agreed' : 'Not given',
    );
  }
}

class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget card(int rows) => AppCard(
      child: Column(
        children: [
          for (int i = 0; i < rows; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: i == rows - 1
                    ? null
                    : Border(bottom: BorderSide(color: c.hairline)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SkeletonBox(height: 16, width: 88),
                  SkeletonBox(height: 16, width: 56),
                ],
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SkeletonBox(height: 16, width: 80),
        const SizedBox(height: AppSpace.sectionBottom),
        card(4),
        const SizedBox(height: AppSpace.sectionTop),
        const SkeletonBox(height: 16, width: 110),
        const SizedBox(height: AppSpace.sectionBottom),
        card(3),
        const SizedBox(height: AppSpace.sectionTop),
        const SkeletonBox(height: 16, width: 90),
        const SizedBox(height: AppSpace.sectionBottom),
        card(3),
        const SizedBox(height: AppSpace.cardGap),
        const SkeletonBox(height: AppSize.button, radius: AppRadius.button),
      ],
    );
  }
}
