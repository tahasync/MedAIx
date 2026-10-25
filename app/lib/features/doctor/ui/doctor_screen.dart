/// Find a doctor (mockup `doctor`): pick one symptom, see which specialist
/// fits and why, then share records.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/features.dart';
import '../../../core/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../../reports/data/reports_repository.dart';
import '../data/doctor_repository.dart';
import '../providers/doctor_providers.dart';

class DoctorScreen extends ConsumerStatefulWidget {
  const DoctorScreen({super.key});

  @override
  ConsumerState<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends ConsumerState<DoctorScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<String>> symptoms = ref.watch(symptomsProvider);
    final String? selected = _selected;

    return AppScaffold(
      body: AppScreen(
        header: const ScreenHeader(
          title: 'Find a doctor',
          subtitle: 'What’s bothering you?',
          showBack: true,
        ),
        children: [
          StateSwitcher(
            child: symptoms.when(
              skipLoadingOnRefresh: true,
              loading: () => const _ChipsSkeleton(
                key: ValueKey<String>('symptoms-loading'),
              ),
              error: (error, _) => ErrorCard(
                key: const ValueKey<String>('symptoms-error'),
                title: 'Couldn’t load symptoms',
                message: error is RepositoryException
                    ? error.message
                    : 'Could not reach the MedAIx service.',
                dataSafety: 'Nothing was changed on your account.',
                onPrimary: () => ref.invalidate(symptomsProvider),
              ),
              data: (list) => Wrap(
                key: const ValueKey<String>('symptoms'),
                spacing: AppSpace.chipGap,
                runSpacing: AppSpace.chipGap,
                children: [
                  for (final String s in list)
                    AppChip(
                      label: s,
                      selected: s == selected,
                      onTap: () => setState(() => _selected = s),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          StateSwitcher(
            child: selected == null
                ? const _PickPrompt(key: ValueKey<String>('no-symptom'))
                : _Recommendation(
                    key: ValueKey<String>('match-$selected'),
                    symptom: selected,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Mockup `.card.empty` with just the muted line.
class _PickPrompt extends StatelessWidget {
  const _PickPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 26),
      child: Text(
        'Pick a symptom to see which specialist fits.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.muted),
      ),
    );
  }
}

class _Recommendation extends ConsumerWidget {
  const _Recommendation({super.key, required this.symptom});

  final String symptom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<SpecialistMatch> match = ref.watch(
      specialistMatchProvider(symptom),
    );
    return match.when(
      skipLoadingOnRefresh: true,
      loading: () => const SkeletonCard(height: 196),
      error: (error, _) => ErrorCard(
        title: 'Couldn’t find a match',
        message: error is RepositoryException
            ? error.message
            : 'Could not reach the MedAIx service.',
        dataSafety: 'Nothing was changed on your account.',
        onPrimary: () => ref.invalidate(specialistMatchProvider(symptom)),
      ),
      data: (m) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CardTag(icon: LucideIcons.stethoscope, label: 'Recommended'),
            Text(m.specialist, style: text.titleLarge),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Why: ${m.why}',
              style: text.bodyMedium?.copyWith(color: c.muted),
            ),
            if (ref.watch(featuresProvider).share) ...[
              const SizedBox(height: AppSpace.lg),
              PrimaryButton(
                label: 'Share my records',
                onPressed: () => context.go(AppRoutes.share),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Four chip-shaped placeholders while symptoms load.
class _ChipsSkeleton extends StatelessWidget {
  const _ChipsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: AppSpace.chipGap,
      runSpacing: AppSpace.chipGap,
      children: [
        SkeletonBox(height: AppSize.chip, width: 150, radius: AppRadius.chip),
        SkeletonBox(height: AppSize.chip, width: 96, radius: AppRadius.chip),
        SkeletonBox(height: AppSize.chip, width: 88, radius: AppRadius.chip),
        SkeletonBox(height: AppSize.chip, width: 92, radius: AppRadius.chip),
      ],
    );
  }
}
