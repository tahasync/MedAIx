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
import '../../../data/api/api_client.dart';
import '../../../theme/app_theme.dart';
import '../../auth/data/session_errors.dart';
import '../../auth/providers/auth_providers.dart';
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
    final bool firstRun = latest.hasValue && latest.valueOrNull == null;
    final bool sessionExpired =
        (trends.hasError && isSessionExpired(trends.error)) ||
        (latest.hasError && isSessionExpired(latest.error));

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
          if (sessionExpired)
            ErrorState.sessionExpired(
              onPrimary: () =>
                  ref.read(authControllerProvider.notifier).expireSession(),
            )
          else if (firstRun)
            BentoGrid(
              children: [
                BentoTile(
                  key: const ValueKey<String>('first-run-hero'),
                  span: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const IconTile(icon: LucideIcons.filePlus2),
                      const SizedBox(height: AppSpace.lg),
                      Text(
                        'Add your first report',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        'Add a lab report to see each value explained in plain language.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.colors.muted,
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      PrimaryButton(
                        label: 'Add a report',
                        icon: LucideIcons.upload,
                        onPressed: () => context.go(AppRoutes.upload),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            BentoGrid(
              children: [
                if (features.trends && !trends.hasError)
                  BentoTile(
                    key: const ValueKey<String>('home-insight-tile'),
                    span: 2,
                    automated: trends.valueOrNull?.insight != null,
                    child: StateSwitcher(
                      child: trends.when(
                        skipLoadingOnRefresh: true,
                        loading: () => const Column(
                          key: ValueKey<String>('insight-loading'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(height: 16, width: 130),
                            SizedBox(height: AppSpace.lg),
                            SkeletonBox(height: 24, width: 240),
                            SizedBox(height: AppSpace.sm),
                            SkeletonBox(height: 16),
                          ],
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (overview) =>
                            _HomeInsightContent(overview: overview),
                      ),
                    ),
                  ),
                BentoTile(
                  key: const ValueKey<String>('add-report-tile'),
                  span: 1,
                  onTap: () => context.go(AppRoutes.upload),
                  semanticsLabel: 'Add a report',
                  child: const _HomeActionContent(
                    icon: LucideIcons.upload,
                    label: 'Add a report',
                  ),
                ),
                if (features.trends)
                  BentoTile(
                    key: const ValueKey<String>('trends-tile'),
                    span: 1,
                    onTap: () => context.go(AppRoutes.trends),
                    semanticsLabel: 'See my trends',
                    child: const _HomeActionContent(
                      icon: LucideIcons.trendingUp,
                      label: 'See my trends',
                    ),
                  ),
                if (features.wellness)
                  BentoTile(
                    key: const ValueKey<String>('habit-score-tile'),
                    span: 2,
                    child: StateSwitcher(
                      child: habits.when(
                        skipLoadingOnRefresh: true,
                        loading: () => const SkeletonBox(
                          key: ValueKey<String>('habits-loading'),
                          height: 76,
                        ),
                        error: (_, _) => ErrorCard(
                          key: const ValueKey<String>('habits-error'),
                          title: 'Couldn’t load your habit score',
                          message: 'Try refreshing today’s habit log.',
                          dataSafety: 'Your saved habit entries are safe.',
                          onPrimary: () => ref.invalidate(habitTodayProvider),
                        ),
                        data: (day) => _HabitCard(
                          key: const ValueKey<String>('habits'),
                          day: day,
                        ),
                      ),
                    ),
                  ),
                BentoTile(
                  key: const ValueKey<String>('latest-report-tile'),
                  span: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Latest report',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpace.md),
                      StateSwitcher(
                        child: latest.when(
                          skipLoadingOnRefresh: true,
                          loading: () => SlowOperationHint(
                            pending: true,
                            onRetry: () => ref.invalidate(reportsListProvider),
                            child: const SkeletonBox(
                              key: ValueKey<String>('latest-loading'),
                              height: 64,
                            ),
                          ),
                          error: (error, _) =>
                              error is RepositoryException &&
                                  error.cause is ApiException &&
                                  (error.cause! as ApiException).statusCode !=
                                      null &&
                                  (error.cause! as ApiException).statusCode! >=
                                      500
                              ? ErrorState.serverError(
                                  key: const ValueKey<String>(
                                    'latest-server-error',
                                  ),
                                  onPrimary: () =>
                                      ref.invalidate(reportsListProvider),
                                  onSecondary: () => showSupportSheet(context),
                                )
                              : ErrorCard(
                                  key: const ValueKey<String>('latest-error'),
                                  title: 'Couldn’t load your reports',
                                  message: error is RepositoryException
                                      ? error.message
                                      : 'Could not reach the MedAIx service.',
                                  dataSafety:
                                      'Your reports are still saved on your account.',
                                  onPrimary: () =>
                                      ref.invalidate(reportsListProvider),
                                ),
                          data: (report) => report == null
                              ? const SizedBox.shrink()
                              : _LatestReportContent(
                                  report: report,
                                  onTap: () =>
                                      context.go(AppRoutes.report(report.id)),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HomeActionContent extends StatelessWidget {
  const _HomeActionContent({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconTile(icon: icon),
      const SizedBox(height: AppSpace.lg),
      Text(label, style: Theme.of(context).textTheme.titleSmall),
    ],
  );
}

class _HomeInsightContent extends StatelessWidget {
  const _HomeInsightContent({required this.overview});

  final TrendOverview overview;

  @override
  Widget build(BuildContext context) {
    final insight = overview.insight;
    if (insight == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTag(icon: LucideIcons.trendingUp, label: 'Trends'),
          Text(
            'Upload one more report to see trends',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            overview.reportsCount == 0
                ? 'Upload two reports with the same values to see how they change.'
                : 'You have one report. Upload another with the same values to see how they change.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.colors.muted),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CardTag(icon: LucideIcons.sparkles, label: 'Automated insight'),
        Text(insight.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpace.sm),
        Text(
          insight.body,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.colors.muted),
        ),
        const SizedBox(height: AppSpace.sm),
        LinkButton(
          label: 'See ${insight.marker} trend',
          onPressed: () => context.go(
            '${AppRoutes.trends}?marker=${Uri.encodeQueryComponent(insight.marker)}',
          ),
        ),
      ],
    );
  }
}

class _LatestReportContent extends StatelessWidget {
  const _LatestReportContent({required this.report, required this.onTap});

  final LabReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${report.title}, ${report.dateLabel}, ${report.statusText}',
    child: InkWell(
      onTap: onTap,
      borderRadius: AppRadius.tileAll,
      child: Row(
        children: [
          const IconTile(icon: LucideIcons.fileText),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  report.dateLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.colors.muted),
                ),
                Text(
                  report.statusText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          ExcludeSemantics(
            child: Icon(
              LucideIcons.chevronRight,
              size: AppSize.icon,
              color: context.colors.text,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Home habit summary: a useful activity mark, explicit score, real progress,
/// next step, and a clear route into Wellness.
class _HabitCard extends StatelessWidget {
  const _HabitCard({super.key, required this.day});

  final WellnessDay day;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final int score = day.habitScore;
    return Row(
      children: [
        const IconTile(
          icon: LucideIcons.activity,
          size: 64,
          iconSize: 30,
          radius: AppRadius.tile,
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
              const SizedBox(height: AppSpace.md),
              ProgressBar(
                value: score / 100,
                semanticLabel: 'Habit score progress: $score of 100',
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
    );
  }
}
