/// Trends (mockup `trends`). Without `?marker=` it lists every value the
/// server tracks across the user's reports; with one it shows that marker's
/// history as a flat line chart with a reference band and reading list,
/// and the alert card. Values come from `GET /risk-trends` and are shown
/// exactly as returned.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../data/report_models.dart';
import '../data/severity.dart';

/// Mockup `spark()` at 300 × 90; a touch taller so the 5 px dots clear.
const double trendChartHeight = 110;

/// Primary line and dots over a shaded reference range.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.series});

  final TrendSeries series;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final List<TrendPoint> points = series.points;
    final List<double> ys = <double>[...points.map((p) => p.value)];
    if (series.low case final double low) ys.add(low);
    if (series.high case final double high) ys.add(high);
    double minY = ys.reduce((a, b) => a < b ? a : b);
    double maxY = ys.reduce((a, b) => a > b ? a : b);
    final double pad = (maxY - minY) == 0 ? 1 : (maxY - minY) * 0.25;
    minY -= pad;
    maxY += pad;
    final List<double> xs = points.map(_dayNumber).toList();
    final bool sameDay = xs.first == xs.last;
    final double minX = sameDay ? xs.first - 1 : xs.first;
    final double maxX = sameDay ? xs.last + 1 : xs.last;

    return LineChart(
      duration: AppMotion.of(context, AppMotion.slow),
      curve: AppMotion.curve,
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.none(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          show: true,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              interval: maxY - minY,
              getTitlesWidget: (value, meta) {
                // fl_chart aligns interval ticks to zero and also adds both
                // data bounds. That can put an interior tick right beside
                // the maximum on narrow phone charts. Keep only the bounds.
                final double tolerance = (meta.max - meta.min).abs() * 1e-9;
                final bool atMin = (value - meta.min).abs() <= tolerance;
                final bool atMax = (value - meta.max).abs() <= tolerance;
                if (!atMin && !atMax) return const SizedBox.shrink();
                return Text(
                  _formatAxisValue(value),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: c.muted),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              // Date-valued x coordinates can span months or years. Asking
              // fl_chart for its default interval creates many synthetic day
              // ticks; show only the real endpoints and list every exact
              // report date below the plot instead.
              interval: maxX - minX,
              getTitlesWidget: (value, meta) {
                final double edgeTolerance = (maxX - minX) / 10;
                final bool atStart = (value - minX).abs() <= edgeTolerance;
                final bool atEnd = (value - maxX).abs() <= edgeTolerance;
                if (!atStart && !atEnd) return const SizedBox.shrink();
                if (sameDay && atEnd) return const SizedBox.shrink();
                final DateTime date = atStart
                    ? points.first.date
                    : points.last.date;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _axisDate(date),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: c.muted),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((spot) {
              final int index = spot.spotIndex;
              final TrendPoint point = points[index];
              final String source = switch (point.dateSource) {
                'report' => 'Report date',
                'sample' => 'Sample date',
                _ => 'Upload date',
              };
              return LineTooltipItem(
                '$source\n${_fullDate(point.date)}\n'
                        '${formatTrendValue(point.value)} ${series.unit}'
                    .trim(),
                TextStyle(color: c.text, fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: series.low != null && series.high != null
              ? <HorizontalRangeAnnotation>[
                  HorizontalRangeAnnotation(
                    y1: series.low!,
                    y2: series.high!,
                    color: c.ok.withValues(alpha: 0.12),
                  ),
                ]
              : const <HorizontalRangeAnnotation>[],
        ),
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            spots: <FlSpot>[
              for (int i = 0; i < points.length; i++)
                FlSpot(xs[i], points[i].value),
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

/// Exact dates and the date source for each plotted result.
class PointLabels extends StatelessWidget {
  const PointLabels({super.key, required this.series});

  final TrendSeries series;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextStyle? style = Theme.of(context).textTheme.bodySmall;
    final List<TrendPoint> points = series.points;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dates use the report date when available; otherwise the upload date.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: c.muted),
        ),
        if (series.unitCorrected)
          Text(
            'Unit corrected from the scan',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: c.muted),
          ),
        const SizedBox(height: AppSpace.sm),
        for (final TrendPoint point in points)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.calendarDays,
                      size: AppSize.iconSmall,
                      color: c.muted,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        '${_readableDate(point.date)} · ${formatTrendValue(point.value)} ${series.unit}'
                            .trim(),
                        style: style,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSize.iconSmall + AppSpace.sm,
                    top: AppSpace.xs,
                  ),
                  child: StatusLabel(
                    status: severityStatus(point.severity),
                    text: severityLabel(point.severity),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _readableDate(DateTime date) =>
    '${date.day} ${_monthAbbreviation(date.month)} ${date.year}';

double _dayNumber(TrendPoint point) =>
    point.date.millisecondsSinceEpoch / Duration.millisecondsPerDay;

String _fullDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _axisDate(DateTime date) =>
    '${_monthAbbreviation(date.month)} ${date.day}';

String _monthAbbreviation(int month) => const <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month - 1];

String formatTrendValue(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

String _formatAxisValue(double value) {
  final double rounded = double.tryParse(value.toStringAsPrecision(4)) ?? value;
  return formatTrendValue(rounded);
}
