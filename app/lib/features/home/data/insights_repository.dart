/// The AI insight shown on Home and the marker trends it links to.
///
/// Backed by `GET /risk-trends` (Sprint 3): the server parses every stored
/// report, groups values by marker and applies deterministic rules. Values
/// are shown exactly as the server returns them; nothing is recomputed here.
library;

import '../../reports/data/report_models.dart';

class Insight {
  const Insight({
    required this.title,
    required this.body,
    required this.marker,
  });

  factory Insight.fromJson(Map<String, dynamic> json) => Insight(
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    marker: json['marker'] as String? ?? '',
  );

  /// e.g. "Your HbA1c has risen across 3 reports".
  final String title;

  /// e.g. "5.9 in March to 6.4 now. Worth raising with your doctor."
  final String body;

  /// Marker the Trends screen should open on.
  final String marker;
}

/// Which way a marker moved over its last readings.
enum TrendDirection { rising, falling, stable }

extension TrendDirectionX on TrendDirection {
  String get label => switch (this) {
    TrendDirection.rising => 'Rising',
    TrendDirection.falling => 'Falling',
    TrendDirection.stable => 'Stable',
  };

  static TrendDirection parse(String? raw) => switch (raw) {
    'rising' => TrendDirection.rising,
    'falling' => TrendDirection.falling,
    _ => TrendDirection.stable,
  };
}

/// One marker's row on the Trends overview.
class MarkerTrend {
  const MarkerTrend({
    required this.marker,
    required this.unit,
    required this.focus,
    required this.direction,
    required this.latestStatus,
    required this.pointCount,
    required this.series,
  });

  final String marker;
  final String unit;

  /// True when the marker matters for one of the user's stated conditions.
  final bool focus;
  final TrendDirection direction;
  final ValueStatus latestStatus;
  final int pointCount;

  /// The chart data for this marker (always present; may hold one point).
  final TrendSeries series;

  bool get hasAlert => series.alertTitle != null;
}

/// Everything `GET /risk-trends` returned, for the overview screen.
class TrendOverview {
  const TrendOverview({
    required this.reportsCount,
    required this.needsReports,
    required this.insight,
    required this.trends,
  });

  final int reportsCount;

  /// True while fewer than two reports exist: the UI shows its empty state.
  final bool needsReports;
  final Insight? insight;
  final List<MarkerTrend> trends;

  MarkerTrend? byMarker(String marker) {
    final String key = _normalise(marker);
    for (final MarkerTrend t in trends) {
      if (_normalise(t.marker) == key) return t;
    }
    return null;
  }

  static String _normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

abstract class InsightsRepository {
  /// null when there is nothing worth surfacing yet.
  Future<Insight?> homeInsight();

  /// History of one marker across reports, or null when there is not enough
  /// data to chart.
  Future<TrendSeries?> trend({String? marker});

  /// Every tracked marker, for the Trends overview.
  Future<TrendOverview> overview();
}

/// Maps the `/risk-trends` JSON onto the domain models.
TrendOverview trendOverviewFromJson(Map<String, dynamic> json) {
  final Object? insightJson = json['insight'];
  final List<dynamic> rows = json['trends'] as List<dynamic>? ?? <dynamic>[];
  return TrendOverview(
    reportsCount: (json['reports_count'] as num?)?.toInt() ?? 0,
    needsReports: json['needs_reports'] as bool? ?? true,
    insight: insightJson is Map<String, dynamic>
        ? Insight.fromJson(insightJson)
        : null,
    trends: rows
        .whereType<Map<String, dynamic>>()
        .map(markerTrendFromJson)
        .toList(),
  );
}

MarkerTrend markerTrendFromJson(Map<String, dynamic> json) {
  final String rawMarker = json['marker'] as String? ?? '';
  final String marker = _validMarker(rawMarker)
      ? rawMarker.trim()
      : 'Lab value';
  final String unit = json['unit'] as String? ?? '';
  final Map<String, dynamic> range =
      json['range'] as Map<String, dynamic>? ?? const <String, dynamic>{};
  final Map<String, dynamic>? alert = json['alert'] as Map<String, dynamic>?;
  final List<Map<String, dynamic>> rawPoints =
      (json['points'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
  final List<TrendPoint> points = <TrendPoint>[
    for (final Map<String, dynamic> p in rawPoints)
      if (p['value'] is num &&
          p['date'] is String &&
          _isIsoDate(p['date'] as String) &&
          (p['date_source'] == 'report' || p['date_source'] == 'upload'))
        TrendPoint(
          date: DateTime.parse('${p['date']}T00:00:00Z'),
          dateSource: p['date_source'] as String,
          value: (p['value'] as num).toDouble(),
        ),
  ];
  final double? high = (range['high'] as num?)?.toDouble();
  final double? low = (range['low'] as num?)?.toDouble();
  final String? lastStatus = rawPoints.isEmpty
      ? null
      : rawPoints.last['status'] as String?;

  return MarkerTrend(
    marker: marker,
    unit: unit,
    focus: json['focus'] as bool? ?? false,
    direction: TrendDirectionX.parse(json['direction'] as String?),
    latestStatus: _statusFrom(lastStatus),
    pointCount: points.length,
    series: TrendSeries(
      marker: marker,
      unit: unit,
      points: points,
      // The dashed line is the upper limit; markers with only a lower limit
      // (HDL) draw that instead.
      threshold: high ?? low,
      rangeLabel: _rangeLabel(points.length, points, range['label'] as String?),
      alertTitle: alert?['title'] as String?,
      alertBody: alert?['body'] as String?,
    ),
  );
}

ValueStatus _statusFrom(String? raw) => switch (raw) {
  'ok' => ValueStatus.ok,
  'warn' => ValueStatus.warn,
  'error' => ValueStatus.error,
  _ => ValueStatus.neutral,
};

/// "4 reports · Mar to Oct" — the subtitle under the marker title. Falls
/// back to the server's range label when there is a single point.
String _rangeLabel(int count, List<TrendPoint> points, String? range) {
  if (count >= 2) {
    return '$count results · ${_dateLabel(points.first)} to '
        '${_dateLabel(points.last)}';
  }
  if (count == 1) return '1 result · ${_dateLabel(points.first)}';
  return range ?? '';
}

String _dateLabel(TrendPoint point) =>
    '${_dateSourceLabel(point.dateSource)} '
    '${point.date.year.toString().padLeft(4, '0')}-'
    '${point.date.month.toString().padLeft(2, '0')}-'
    '${point.date.day.toString().padLeft(2, '0')}';

bool _isIsoDate(String value) =>
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
    DateTime.tryParse(value)?.toIso8601String().substring(0, 10) == value;

String _dateSourceLabel(String source) => switch (source) {
  'report' => 'Report',
  'sample' => 'Sample',
  _ => 'Uploaded',
};

bool _validMarker(String value) {
  final String name = value.trim();
  if (name.isEmpty ||
      name.length > 36 ||
      name.split(RegExp(r'\s+')).length > 5) {
    return false;
  }
  if (RegExp(
    r'\b(patient|registered|visit|number|collected|age|sex|name|date|report)\b',
    caseSensitive: false,
  ).hasMatch(name)) {
    return false;
  }
  return RegExp(r"^[A-Za-z][A-Za-z0-9 ()+./-]*$").hasMatch(name);
}
