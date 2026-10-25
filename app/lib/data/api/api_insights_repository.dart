/// `GET /risk-trends` behind [InsightsRepository].
///
/// One request feeds Home's insight card, the Trends overview and every
/// per-marker chart, so the response is memoised for a short while and the
/// three readers share it instead of hitting the server three times.
library;

import '../../features/home/data/insights_repository.dart';
import '../../features/reports/data/report_models.dart';
import '../../features/reports/data/reports_repository.dart';
import 'api_client.dart';

class ApiInsightsRepository implements InsightsRepository {
  ApiInsightsRepository(
    this._api, {
    this.cacheFor = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ApiClient _api;

  /// How long a fetched overview is reused before asking the server again.
  /// Short on purpose: an upload invalidates the providers anyway, and this
  /// only has to cover the Home → Trends → chart hop.
  final Duration cacheFor;
  final DateTime Function() _now;

  TrendOverview? _cached;
  DateTime? _cachedAt;
  Future<TrendOverview>? _inFlight;

  @override
  Future<Insight?> homeInsight() async => (await overview()).insight;

  @override
  Future<TrendSeries?> trend({String? marker}) async {
    final TrendOverview data = await overview();
    if (data.trends.isEmpty) return null;
    final MarkerTrend? match = marker == null || marker.trim().isEmpty
        ? _preferred(data)
        : data.byMarker(marker);
    if (match == null) return null;
    return match.series;
  }

  /// The marker the screen opens on when none was requested: the insight's,
  /// else the first alert, else the first focus marker, else the first row.
  MarkerTrend? _preferred(TrendOverview data) {
    final String? wanted = data.insight?.marker;
    if (wanted != null) {
      final MarkerTrend? m = data.byMarker(wanted);
      if (m != null) return m;
    }
    for (final MarkerTrend t in data.trends) {
      if (t.hasAlert) return t;
    }
    for (final MarkerTrend t in data.trends) {
      if (t.focus) return t;
    }
    return data.trends.first;
  }

  @override
  Future<TrendOverview> overview() {
    final TrendOverview? cached = _cached;
    final DateTime? at = _cachedAt;
    if (cached != null && at != null && _now().difference(at) < cacheFor) {
      return Future<TrendOverview>.value(cached);
    }
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<TrendOverview> _load() async {
    try {
      final Map<String, dynamic> json = await _api.fetchRiskTrends();
      final TrendOverview data = trendOverviewFromJson(json);
      _cached = data;
      _cachedAt = _now();
      return data;
    } on ApiException catch (error) {
      final int? status = error.statusCode;
      throw RepositoryException(
        error.message,
        canRetry: status == null || status >= 500,
        cause: error,
      );
    }
  }

  /// Forget the memoised response (after an upload, for instance).
  void invalidate() {
    _cached = null;
    _cachedAt = null;
  }
}
