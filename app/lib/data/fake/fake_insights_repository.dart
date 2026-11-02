/// Fake repository implementation isolated by feature responsibility.
library;

import '../../features/home/data/insights_repository.dart';
import '../../features/reports/data/report_models.dart';
import 'fake_reports_repository.dart';

/// Synthetic in-memory implementation for tests and local demos.
class FakeInsightsRepository implements InsightsRepository {
  FakeInsightsRepository({
    this.latency = const Duration(milliseconds: 200),
    this.insight = const Insight(
      title: 'Sample HbA1c trend',
      body: 'Demo values: 5.9 to 6.4 across four sample readings.',
      marker: 'HbA1c',
    ),
    this.reportsCount = 4,
  });

  final Duration latency;
  final Insight? insight;

  /// Fewer than two reports means "not enough data" everywhere.
  final int reportsCount;

  bool get _needsReports => reportsCount < 2;

  @override
  Future<Insight?> homeInsight() async {
    await Future<void>.delayed(latency);
    return _needsReports ? null : insight;
  }

  @override
  Future<TrendSeries?> trend({String? marker}) async {
    await Future<void>.delayed(latency);
    if (_needsReports) return null;
    if (marker == null || marker.trim().isEmpty) return sampleTrends().first;
    final String key = marker.toLowerCase().replaceAll(' ', '');
    for (final TrendSeries s in sampleTrends()) {
      if (s.marker.toLowerCase().replaceAll(' ', '') == key) return s;
    }
    return null;
  }

  @override
  Future<TrendOverview> overview() async {
    await Future<void>.delayed(latency);
    if (_needsReports) {
      return TrendOverview(
        reportsCount: reportsCount,
        needsReports: true,
        insight: null,
        trends: const <MarkerTrend>[],
      );
    }
    final List<TrendSeries> series = sampleTrends();
    return TrendOverview(
      reportsCount: reportsCount,
      needsReports: false,
      insight: insight,
      trends: <MarkerTrend>[
        MarkerTrend(
          marker: series[0].marker,
          unit: series[0].unit,
          focus: true,
          direction: TrendDirection.rising,
          latestStatus: ValueStatus.error,
          pointCount: series[0].points.length,
          series: series[0],
        ),
        MarkerTrend(
          marker: series[1].marker,
          unit: series[1].unit,
          focus: true,
          direction: TrendDirection.stable,
          latestStatus: ValueStatus.ok,
          pointCount: series[1].points.length,
          series: series[1],
        ),
        MarkerTrend(
          marker: series[2].marker,
          unit: series[2].unit,
          focus: false,
          direction: TrendDirection.falling,
          latestStatus: ValueStatus.ok,
          pointCount: series[2].points.length,
          series: series[2],
        ),
      ],
    );
  }

  /// Obviously-sample histories: HbA1c (alert), fasting glucose, LDL.
  static List<TrendSeries> sampleTrends() => <TrendSeries>[
    FakeReportsRepository.sampleTrend(),
    TrendSeries(
      marker: 'Fasting glucose',
      unit: 'mg/dL',
      points: <TrendPoint>[
        TrendPoint(
          date: DateTime.utc(2026, 3, 1),
          dateSource: 'sample',
          value: 92,
          severity: 'normal',
        ),
        TrendPoint(
          date: DateTime.utc(2026, 6, 1),
          dateSource: 'sample',
          value: 95,
          severity: 'normal',
        ),
        TrendPoint(
          date: DateTime.utc(2026, 8, 1),
          dateSource: 'sample',
          value: 94,
          severity: 'normal',
        ),
        TrendPoint(
          date: DateTime.utc(2026, 10, 1),
          dateSource: 'sample',
          value: 96,
          severity: 'normal',
        ),
      ],
      threshold: 99,
      rangeLabel: 'Sample data · 4 results',
    ),
    TrendSeries(
      marker: 'LDL',
      unit: 'mg/dL',
      points: <TrendPoint>[
        TrendPoint(
          date: DateTime.utc(2026, 3, 1),
          dateSource: 'sample',
          value: 118,
          severity: 'high',
        ),
        TrendPoint(
          date: DateTime.utc(2026, 8, 1),
          dateSource: 'sample',
          value: 104,
          severity: 'high',
        ),
        TrendPoint(
          date: DateTime.utc(2026, 10, 1),
          dateSource: 'sample',
          value: 97,
          severity: 'normal',
        ),
      ],
      threshold: 100,
      rangeLabel: 'Sample data · 3 results',
    ),
  ];
}

/// In-memory `/profile`. Applies partial drafts the way the server does
/// (age from date of birth, consent stamped, `onboarding_complete` derived,
/// gender-filtered answers only kept for the group they apply to).
