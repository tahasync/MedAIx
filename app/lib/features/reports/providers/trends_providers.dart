/// Marker history for the Trends screen. `null` from [trendSeriesProvider]
/// means there is not enough data to chart yet (the screen shows its empty
/// state); [trendOverviewProvider] lists every tracked marker.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories.dart';
import '../../home/data/insights_repository.dart';
import '../data/report_models.dart';

/// Marker the Trends screen opens on when none is given.
const String kDefaultTrendMarker = 'HbA1c';

final trendSeriesProvider = FutureProvider.autoDispose
    .family<TrendSeries?, String>(
      (ref, marker) =>
          ref.watch(insightsRepositoryProvider).trend(marker: marker),
    );

/// Every marker the server tracks across the user's reports.
final trendOverviewProvider = FutureProvider.autoDispose<TrendOverview>(
  (ref) => ref.watch(insightsRepositoryProvider).overview(),
);
