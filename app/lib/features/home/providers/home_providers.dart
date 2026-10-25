/// Home-only state: the AI insight and today's habit score. Reports come
/// from `features/reports/providers/reports_providers.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories.dart';
import '../../wellness/data/wellness_repository.dart';
import '../data/insights_repository.dart';

/// The insight card on Home, or null when there is nothing to surface.
final homeInsightProvider = FutureProvider<Insight?>(
  (ref) => ref.watch(insightsRepositoryProvider).homeInsight(),
);

/// Today's habits, for the habit-score card.
final habitTodayProvider = FutureProvider<WellnessDay>(
  (ref) => ref.watch(wellnessRepositoryProvider).today(),
);

/// "Good morning" / "Good afternoon" / "Good evening" for [hour] (0–23).
String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}
