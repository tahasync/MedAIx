/// Home tab (mockup `home`): greeting, AI insight, four quick actions, the
/// habit-score card and the latest report.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/features.dart';
import '../../../core/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../../profile/providers/profile_providers.dart';
import '../../reports/data/report_models.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/providers/reports_providers.dart';
import '../../reports/providers/trends_providers.dart';
import '../../wellness/data/wellness_repository.dart';
import '../data/insights_repository.dart';
import '../providers/home_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) {
    ref.invalidate(trendOverviewProvider);
    ref.invalidate(habitTodayProvider);
    ref.invalidate(reportsListProvider);
    return Future.wait<void>(<Future<void>>[
      ref.read(trendOverviewProvider.future).then((_) {}, onError: (_) {}),
      ref.read(habitTodayProvider.future).then((_) {}, onError: (_) {}),
      ref.read(reportsListProvider.future).then((_) {}, onError: (_) {}),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The h1 is the patient's name (mockup); "Welcome" until one is set.
    final String? storedName = ref.watch(profileProvider).valueOrNull?.name;
    final String name = (storedName == null || storedName.trim().isEmpty)
        ? 'Welcome'
        : storedName.trim();
    final AsyncValue<TrendOverview> trends = ref.watch(trendOverviewProvider);
    final AsyncValue<WellnessDay> habits = ref.watch(habitTodayProvider);
    final AsyncValue<LabReport?> latest = ref.watch(latestReportProvider);
    final FeatureFlags features = ref.watch(featuresProvider);

    return AppScaffold(
      body: AppScreen(
        onRefresh: () => _refresh(ref),
        header: ScreenHeader(
          title: name,
          subtitle: greetingForHour(DateTime.now().hour),
          trailing: features.reminders
              ? AppIconButton(
                  icon: LucideIcons.bell,
                  label: 'Reminders',
                  onPressed: () => context.go(AppRoutes.reminders),
                )
              : null,
        ),
        children: [
          // Real trends only: invented sample insights stay in fake-data
          // mode. With fewer than two reports the card explains what to do.
          if (features.trends)
            StateSwitcher(
              child: trends.when(
                skipLoadingOnRefresh: true,
                loading: () => const Padding(
                  key: ValueKey<String>('insight-loading'),
                  padding: EdgeInsets.only(bottom: AppSpace.cardGap),
                  child: SkeletonCard(height: 168),
                ),
                error: (_, _) => const SizedBox.shrink(
                  key: ValueKey<String>('insight-error'),
                ),
                data: (overview) => Padding(
                  key: ValueKey<String>(
                    overview.insight == null ? 'insight-empty' : 'insight',
                  ),
                  padding: const EdgeInsets.only(bottom: AppSpace.cardGap),
                  child: overview.insight == null
                      ? AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const CardTag(
                                icon: LucideIcons.trendingUp,
                                label: 'Trends',
                              ),
                              Text(
                                'Upload one more report to see trends',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: AppSpace.sm),
                              Text(
                                overview.reportsCount == 0
                                    ? 'Upload two reports with the same values '
                                          'to see how they change.'
                                    : 'You have one report. Upload another with '
                                          'the same values to see how they change.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: context.colors.muted),
                              ),
                              const SizedBox(height: AppSpace.lg),
                              PrimaryButton(
                                label: 'Upload report',
                                icon: LucideIcons.upload,
                                compact: true,
                                onPressed: () => context.go(AppRoutes.upload),
                              ),
                            ],
                          ),
                        )
                      : AiInsightCard(
                          title: overview.insight!.title,
                          body: overview.insight!.body,
                          actionLabel: 'See the trend',
                          onAction: () => context.go(
                            '${AppRoutes.trends}?marker=${Uri.encodeQueryComponent(overview.insight!.marker)}',
                          ),
                        ),
                ),
              ),
            ),
          _QuickActions(features: features),
          const SizedBox(height: AppSpace.cardGap),
          if (features.wellness)
            StateSwitcher(
              child: habits.when(
                skipLoadingOnRefresh: true,
                loading: () => const SkeletonCard(
                  key: ValueKey<String>('habits-loading'),
                  height: 100,
                ),
                error: (_, _) => const SizedBox.shrink(
                  key: ValueKey<String>('habits-error'),
                ),
                data: (day) =>
                    _HabitCard(key: const ValueKey<String>('habits'), day: day),
              ),
            ),
          const SectionTitle('Latest report'),
          StateSwitcher(
            child: latest.when(
              skipLoadingOnRefresh: true,
              loading: () => const SkeletonCard(
                key: ValueKey<String>('latest-loading'),
                height: 76,
              ),
              error: (error, _) => ErrorCard(
                key: const ValueKey<String>('latest-error'),
                title: 'Couldn’t load your reports',
                message: error is RepositoryException
                    ? error.message
                    : 'Could not reach the MedAIx service.',
                dataSafety: 'Your reports are still saved on your account.',
                onPrimary: () => ref.invalidate(reportsListProvider),
              ),
              data: (report) => report == null
                  ? EmptyState(
                      key: const ValueKey<String>('latest-empty'),
                      icon: LucideIcons.fileText,
                      title: 'No reports yet',
                      reason:
                          'Add a lab report and we’ll explain every value in '
                          'plain language.',
                      action: PrimaryButton(
                        label: 'Upload report',
                        icon: LucideIcons.upload,
                        onPressed: () => context.go(AppRoutes.upload),
                      ),
                    )
                  : SummaryRow(
                      key: const ValueKey<String>('latest'),
                      icon: const IconTile(icon: LucideIcons.fileText),
                      title: '${report.title}, ${report.dateLabel}',
                      subtitle: report.statusText,
                      onTap: () => context.go(AppRoutes.report(report.id)),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mockup `.grid`: up to 2 × 2 tiles with a 10 px gap, built from the
/// epics this sprint has delivered. Rows of `Expanded` so nothing overflows
/// at 320 dp; an odd last tile keeps its half width.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.features});

  final FeatureFlags features;

  @override
  Widget build(BuildContext context) {
    final List<Widget> tiles = <Widget>[
      TileButton(
        icon: LucideIcons.upload,
        label: 'Upload report',
        onTap: () => context.go(AppRoutes.upload),
      ),
      if (features.meds)
        TileButton(
          icon: LucideIcons.pill,
          label: 'Check medicines',
          onTap: () => context.go(AppRoutes.meds),
        ),
      if (features.scan)
        TileButton(
          icon: LucideIcons.camera,
          label: 'Scan medicine',
          onTap: () => context.go(AppRoutes.scan),
        ),
      if (features.doctorMatch)
        TileButton(
          icon: LucideIcons.stethoscope,
          label: 'Find a doctor',
          onTap: () => context.go(AppRoutes.doctor),
        ),
      // Fills the grid until the mockup's four actions have all shipped;
      // trends stays reachable from the insight card and each report.
      if (features.trends)
        TileButton(
          icon: LucideIcons.trendingUp,
          label: 'View trends',
          onTap: () => context.go(AppRoutes.trends),
        ),
    ].take(4).toList();
    return Column(
      children: [
        for (int i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AppSpace.gridGap),
          _TileRow(
            left: tiles[i],
            right: i + 1 < tiles.length ? tiles[i + 1] : null,
          ),
        ],
      ],
    );
  }
}

/// Two tiles side by side, equal height even when one label wraps.
class _TileRow extends StatelessWidget {
  const _TileRow({required this.left, this.right});

  final Widget left;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: AppSpace.gridGap),
          Expanded(child: right ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}

/// Mockup habit card: ring, "Habit score 72", next step, chevron.
class _HabitCard extends StatelessWidget {
  const _HabitCard({super.key, required this.day});

  final WellnessDay day;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final int score = day.habitScore;
    return AppCard(
      child: Row(
        children: [
          ScoreRing(
            value: score / 100,
            semanticLabel: 'Habit score $score of 100',
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Habit score $score', style: text.titleLarge),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  day.nextStep,
                  style: text.bodySmall?.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.lg),
          AppIconButton(
            icon: LucideIcons.chevronRight,
            label: 'Open wellness',
            onCard: true,
            onPressed: () => context.go(AppRoutes.wellness),
          ),
        ],
      ),
    );
  }
}
