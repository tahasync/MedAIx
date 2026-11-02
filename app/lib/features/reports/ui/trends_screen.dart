/// Trends (mockup `trends`). Without `?marker=` it lists every value the
/// server tracks across the user's reports; with one it shows that marker's
/// history as a flat line chart with a reference band and reading list,
/// and the alert card. Values come from `GET /risk-trends` and are shown
/// exactly as returned.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/features.dart';
import '../../../core/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../../auth/data/session_errors.dart';
import '../../auth/providers/auth_providers.dart';
import '../../home/data/insights_repository.dart';
import '../data/report_models.dart';
import '../data/reports_repository.dart';
import '../data/severity.dart';
import '../providers/trends_providers.dart';
import 'trend_chart.dart';

class TrendsScreen extends ConsumerWidget {
  const TrendsScreen({super.key, this.marker});

  /// From `?marker=`; the overview when absent.
  final String? marker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String m = marker?.trim() ?? '';
    if (m.isEmpty) return const _TrendsOverview();
    return _MarkerTrendScreen(marker: m);
  }
}

/// Every tracked marker, one row each, alerts first.
class _TrendsOverview extends ConsumerWidget {
  const _TrendsOverview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TrendOverview> overview = ref.watch(trendOverviewProvider);
    final TrendOverview? data = overview.valueOrNull;
    final String? subtitle = data == null || data.needsReports
        ? null
        : data.reportsCount == 1
        ? '1 report'
        : '${data.reportsCount} reports';

    return AppScaffold(
      body: AppScreen(
        header: ScreenHeader(
          title: 'Trends',
          subtitle: subtitle,
          showBack: true,
        ),
        onRefresh: () => ref.refresh(trendOverviewProvider.future),
        children: [
          StateSwitcher(
            child: overview.when(
              skipLoadingOnRefresh: true,
              loading: () => const _TrendsLoading(),
              error: (error, _) => isSessionExpired(error)
                  ? ErrorState.sessionExpired(
                      key: const ValueKey<String>('session-expired'),
                      onPrimary: () => ref
                          .read(authControllerProvider.notifier)
                          .expireSession(),
                    )
                  : ErrorCard(
                      key: const ValueKey<String>('trends-error'),
                      title: 'Couldn’t load your trends',
                      message: error is RepositoryException
                          ? error.message
                          : 'Could not reach the MedAIx service.',
                      dataSafety:
                          'Your reports are still saved on your account.',
                      onPrimary: () => ref.invalidate(trendOverviewProvider),
                      secondaryLabel: 'Back to reports',
                      onSecondary: () => context.popOrGo(AppRoutes.reports),
                    ),
              data: (d) => d.needsReports || d.trends.isEmpty
                  ? _NotEnoughReports(
                      key: const ValueKey<String>('trends-empty'),
                      reportsCount: d.reportsCount,
                    )
                  : _OverviewBody(
                      key: const ValueKey<String>('trends'),
                      overview: d,
                    ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          const AppDisclaimer(),
        ],
      ),
    );
  }
}

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({super.key, required this.overview});

  final TrendOverview overview;

  @override
  Widget build(BuildContext context) {
    final Insight? insight = overview.insight;
    final List<MarkerTrend> alerts = overview.trends
        .where((t) => t.hasAlert)
        .toList();
    final List<MarkerTrend> others = overview.trends
        .where((t) => !t.hasAlert)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (insight != null) ...[
          AiInsightCard(
            title: insight.title,
            body: insight.body,
            actionLabel: 'See ${insight.marker} trend',
            onAction: () => context.push(_markerRoute(insight.marker)),
          ),
          const SizedBox(height: AppSpace.cardGap),
        ],
        if (alerts.isNotEmpty) ...[
          const SectionTitle('Worth a look', first: true),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.card),
            child: ListRows(
              rows: <ListRow>[for (final t in alerts) _markerRow(context, t)],
            ),
          ),
        ],
        if (others.isNotEmpty) ...[
          SectionTitle('All values', first: alerts.isEmpty),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.card),
            child: ListRows(
              rows: <ListRow>[for (final t in others) _markerRow(context, t)],
            ),
          ),
        ],
      ],
    );
  }

  ListRow _markerRow(BuildContext context, MarkerTrend t) {
    final String latest = t.series.points.isEmpty
        ? ''
        : '${formatTrendValue(t.series.points.last.value)} ${t.unit}'.trim();
    final String count = t.pointCount == 1
        ? '1 report'
        : '${t.pointCount} reports';
    final String subtitle = latest.isEmpty
        ? count
        : 'Latest $latest · $count${t.direction.label.isEmpty ? '' : ' · ${t.direction.label}'}';
    return ListRow(
      key: ValueKey<String>('trend-row-${t.marker}'),
      title: t.marker,
      subtitle: subtitle,
      leading: IconTile(
        icon: switch (t.direction) {
          TrendDirection.rising => LucideIcons.trendingUp,
          TrendDirection.falling => LucideIcons.trendingDown,
          TrendDirection.stable => LucideIcons.minus,
          TrendDirection.unavailable => LucideIcons.minus,
        },
      ),
      trailing: StatusLabel(
        status: t.latestStatus,
        text: t.series.points.isEmpty
            ? 'Unrated'
            : severityLabel(t.series.points.last.severity),
      ),
      onTap: () => context.push(_markerRoute(t.marker)),
    );
  }
}

String _markerRoute(String marker) =>
    '${AppRoutes.trends}?marker=${Uri.encodeQueryComponent(marker)}';

class _NotEnoughReports extends StatelessWidget {
  const _NotEnoughReports({super.key, required this.reportsCount});

  final int reportsCount;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: LucideIcons.trendingUp,
      title: 'Not enough reports yet',
      reason: reportsCount == 1
          ? 'You have one report. Upload another with the same values to '
                'see how they change.'
          : 'Upload two or more reports with the same values to see how '
                'they change.',
      action: PrimaryButton(
        label: 'Add a report',
        icon: LucideIcons.upload,
        onPressed: () => context.go(AppRoutes.upload),
      ),
    );
  }
}

/// One marker's chart, labels and alert.
class _MarkerTrendScreen extends ConsumerWidget {
  const _MarkerTrendScreen({required this.marker});

  final String marker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TrendSeries?> series = ref.watch(
      trendSeriesProvider(marker),
    );
    final TrendSeries? value = series.valueOrNull;
    final int reportCount = value?.points.length ?? 0;

    return AppScaffold(
      body: AppScreen(
        header: ScreenHeader(
          title: value == null || value.marker.isEmpty
              ? 'Trend details'
              : '${value.marker} trend',
          subtitle: value == null
              ? null
              : 'From $reportCount ${reportCount == 1 ? 'report' : 'reports'}',
          showBack: true,
        ),
        children: [
          StateSwitcher(
            child: series.when(
              skipLoadingOnRefresh: true,
              loading: () => const _TrendLoading(),
              error: (error, _) => isSessionExpired(error)
                  ? ErrorState.sessionExpired(
                      key: const ValueKey<String>('session-expired'),
                      onPrimary: () => ref
                          .read(authControllerProvider.notifier)
                          .expireSession(),
                    )
                  : ErrorCard(
                      key: const ValueKey<String>('trend-error'),
                      title: 'Couldn’t load this trend',
                      message: error is RepositoryException
                          ? error.message
                          : 'Could not reach the MedAIx service.',
                      dataSafety:
                          'Your reports are still saved on your account.',
                      onPrimary: () =>
                          ref.invalidate(trendSeriesProvider(marker)),
                      secondaryLabel: 'Back to reports',
                      onSecondary: () => context.popOrGo(AppRoutes.reports),
                    ),
              data: (s) => s == null || s.points.isEmpty
                  ? EmptyState(
                      key: const ValueKey<String>('trend-empty'),
                      icon: LucideIcons.trendingUp,
                      title: 'Not enough reports yet',
                      reason:
                          'Upload two or more reports with the same value to '
                          'see how it changes.',
                      action: PrimaryButton(
                        label: 'Add a report',
                        icon: LucideIcons.upload,
                        onPressed: () => context.go(AppRoutes.upload),
                      ),
                    )
                  : _TrendBody(key: const ValueKey<String>('trend'), series: s),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          const AppDisclaimer(),
        ],
      ),
    );
  }
}

class _TrendBody extends StatelessWidget {
  const _TrendBody({super.key, required this.series});

  final TrendSeries series;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String? alertTitle = series.alertTitle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (series.points.length == 1) ...[
                Text(
                  'One reading so far — add another report to see a trend',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: AppSpace.md),
              ],
              if (series.referenceRangeLabel != null) ...[
                Text(
                  series.referenceRangeLabel!.replaceFirst(
                    'Normal range',
                    'Normal',
                  ),
                  style: text.titleSmall,
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              Semantics(
                container: true,
                label: series.semanticDescription,
                image: true,
                child: ExcludeSemantics(
                  child: SizedBox(
                    height: trendChartHeight,
                    child: TrendChart(series: series),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              PointLabels(series: series),
            ],
          ),
        ),
        if (alertTitle != null) ...[
          const SizedBox(height: AppSpace.cardGap),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardTag(
                  icon: LucideIcons.triangleAlert,
                  label: alertTitle,
                  color: c.warn,
                ),
                if (series.alertBody != null)
                  Text(series.alertBody!, style: text.bodyMedium),
                Consumer(
                  builder: (context, ref, _) =>
                      ref.watch(featuresProvider).doctorMatch
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSpace.lg),
                          child: PrimaryButton(
                            label: 'Find a specialist',
                            onPressed: () => context.go(AppRoutes.doctor),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TrendsLoading extends StatelessWidget {
  const _TrendsLoading();

  @override
  Widget build(BuildContext context) => const Column(
    key: ValueKey<String>('trends-loading'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SkeletonCard(height: 84),
      SizedBox(height: AppSpace.cardGap),
      SkeletonCard(height: 136),
      SizedBox(height: AppSpace.cardGap),
      SkeletonCard(height: 136),
    ],
  );
}

class _TrendLoading extends StatelessWidget {
  const _TrendLoading();

  @override
  Widget build(BuildContext context) => const Column(
    key: ValueKey<String>('trend-loading'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SkeletonCard(height: 176),
      SizedBox(height: AppSpace.cardGap),
      SkeletonCard(height: 84),
    ],
  );
}
