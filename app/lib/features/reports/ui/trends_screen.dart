/// Trends (mockup `trends`). Without `?marker=` it lists every value the
/// server tracks across the user's reports; with one it shows that marker's
/// history as a flat line chart with a dashed threshold, the point labels,
/// and the alert card. Values come from `GET /risk-trends` and are shown
/// exactly as returned.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/features.dart';
import '../../../core/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../../home/data/insights_repository.dart';
import '../data/report_models.dart';
import '../data/reports_repository.dart';
import '../providers/trends_providers.dart';

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
              loading: () => const ScreenSkeleton(
                key: ValueKey<String>('trends-loading'),
                rows: 4,
                firstHeight: 120,
              ),
              error: (error, _) => ErrorCard(
                key: const ValueKey<String>('trends-error'),
                title: 'Couldn’t load your trends',
                message: error is RepositoryException
                    ? error.message
                    : 'Could not reach the MedAIx service.',
                dataSafety: 'Your reports are still saved on your account.',
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
            actionLabel: 'See the trend',
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
        const SizedBox(height: AppSpace.cardGap),
        Text(
          'Trends compare the values on your reports. They are information, '
          'not a diagnosis.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.colors.muted),
        ),
      ],
    );
  }

  ListRow _markerRow(BuildContext context, MarkerTrend t) {
    final String latest = t.series.points.isEmpty
        ? ''
        : '${_fmt(t.series.points.last.value)} ${t.unit}'.trim();
    final String count = t.pointCount == 1
        ? '1 report'
        : '${t.pointCount} reports';
    final String subtitle = latest.isEmpty
        ? count
        : 'Latest $latest · $count · ${t.direction.label}';
    return ListRow(
      key: ValueKey<String>('trend-row-${t.marker}'),
      title: t.marker,
      subtitle: subtitle,
      leading: IconTile(
        icon: switch (t.direction) {
          TrendDirection.rising => LucideIcons.trendingUp,
          TrendDirection.falling => LucideIcons.trendingDown,
          TrendDirection.stable => LucideIcons.minus,
        },
      ),
      trailing: StatusLabel(
        status: t.latestStatus,
        text: switch (t.latestStatus) {
          ValueStatus.ok => 'Normal',
          ValueStatus.warn => 'Borderline',
          ValueStatus.error => 'Out of range',
          ValueStatus.neutral => 'Unrated',
        },
      ),
      onTap: () => context.push(_markerRoute(t.marker)),
    );
  }
}

String _markerRoute(String marker) =>
    '${AppRoutes.trends}?marker=${Uri.encodeQueryComponent(marker)}';

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

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
        label: 'Upload report',
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

    return AppScaffold(
      body: AppScreen(
        header: ScreenHeader(
          title: '${series.valueOrNull?.marker ?? marker} trend',
          subtitle: series.valueOrNull?.rangeLabel,
          showBack: true,
        ),
        children: [
          StateSwitcher(
            child: series.when(
              skipLoadingOnRefresh: true,
              loading: () => const Column(
                key: ValueKey<String>('trend-loading'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SkeletonCard(height: 176),
                  SizedBox(height: AppSpace.cardGap),
                  SkeletonCard(height: 150),
                ],
              ),
              error: (error, _) => ErrorCard(
                key: const ValueKey<String>('trend-error'),
                title: 'Couldn’t load this trend',
                message: error is RepositoryException
                    ? error.message
                    : 'Could not reach the MedAIx service.',
                dataSafety: 'Your reports are still saved on your account.',
                onPrimary: () => ref.invalidate(trendSeriesProvider(marker)),
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
                        label: 'Upload report',
                        icon: LucideIcons.upload,
                        onPressed: () => context.go(AppRoutes.upload),
                      ),
                    )
                  : _TrendBody(key: const ValueKey<String>('trend'), series: s),
            ),
          ),
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
              Semantics(
                container: true,
                label: series.semanticDescription,
                image: true,
                child: ExcludeSemantics(
                  child: SizedBox(
                    height: _chartHeight,
                    child: _TrendChart(series: series),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              _PointLabels(series: series),
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

/// Mockup `spark()` at 300 × 90; a touch taller so the 5 px dots clear.
const double _chartHeight = 110;

/// Primary 3 px line with 5 px dots, dashed warn threshold, nothing else.
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.series});

  final TrendSeries series;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final List<TrendPoint> points = series.points;
    final List<double> ys = <double>[
      ...points.map((p) => p.value),
      series.threshold,
    ];
    double minY = ys.reduce((a, b) => a < b ? a : b);
    double maxY = ys.reduce((a, b) => a > b ? a : b);
    final double pad = (maxY - minY) == 0 ? 1 : (maxY - minY) * 0.25;
    minY -= pad;
    maxY += pad;
    final double maxX = points.length == 1 ? 1 : (points.length - 1).toDouble();

    return LineChart(
      duration: AppMotion.of(context, AppMotion.slow),
      curve: AppMotion.curve,
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.none(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: <HorizontalLine>[
            HorizontalLine(
              y: series.threshold,
              color: c.warn,
              strokeWidth: 1,
              dashArray: const <int>[4, 5],
            ),
          ],
        ),
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            spots: <FlSpot>[
              for (int i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].value),
            ],
            color: c.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            isStrokeJoinRound: true,
            dotData: FlDotData(
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(radius: 5, color: c.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Mar 5.9 … Oct 6.4" under the chart, spaced between. Each label gets an
/// equal share so nothing overflows at 320 dp or 200 % text.
class _PointLabels extends StatelessWidget {
  const _PointLabels({required this.series});

  final TrendSeries series;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextStyle? style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: c.muted);
    final List<TrendPoint> points = series.points;
    return Row(
      children: [
        for (int i = 0; i < points.length; i++)
          Expanded(
            child: Text(
              '${points[i].label} ${_fmt(points[i].value)}',
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: points.length == 1
                  ? TextAlign.start
                  : i == 0
                  ? TextAlign.start
                  : i == points.length - 1
                  ? TextAlign.end
                  : TextAlign.center,
            ),
          ),
      ],
    );
  }
}
