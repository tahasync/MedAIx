/// Profile state shared by onboarding, Home (greeting), Profile and More.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories.dart';
import '../../auth/providers/auth_providers.dart';
import '../../home/providers/home_providers.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/providers/reports_providers.dart';
import '../../reports/providers/trends_providers.dart';
import '../../wellness/providers/wellness_providers.dart';
import '../data/profile_repository.dart';

/// Signed-in patient's profile. Refetches when the session changes.
final profileProvider = FutureProvider<PatientProfile>((ref) async {
  final session = ref.watch(authControllerProvider);
  if (session == null) {
    throw const RepositoryException('Please sign in to continue.');
  }
  return ref.watch(profileRepositoryProvider).fetch();
});

/// Save / delete, keeping [profileProvider] in sync.
class ProfileEditor extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<PatientProfile?> save(ProfileDraft draft) async {
    state = const AsyncLoading();
    try {
      final PatientProfile saved = await ref
          .read(profileRepositoryProvider)
          .save(draft);
      ref.invalidate(profileProvider);
      _invalidateHealthViews();
      state = const AsyncData(null);
      return saved;
    } on RepositoryException catch (error, stack) {
      state = AsyncError(error, stack);
      return null;
    }
  }

  Future<bool> delete() async {
    state = const AsyncLoading();
    try {
      await ref.read(profileRepositoryProvider).delete();
      await ref.read(reportsRepositoryProvider).clearHealthData();
      await ref.read(wellnessRepositoryProvider).clearLocal();
      ref.invalidate(profileProvider);
      _invalidateHealthViews(clearReportViews: true);
      state = const AsyncData(null);
      return true;
    } on RepositoryException catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
    }
  }

  /// Profile answers affect condition-aware trends and wellness goals. Clear
  /// those views together with report data after saves and health-data deletion
  /// so a previous account state is never left on screen from provider caches.
  void _invalidateHealthViews({bool clearReportViews = false}) {
    if (clearReportViews) {
      ref.invalidate(reportsListProvider);
      ref.invalidate(latestReportProvider);
      ref.invalidate(reportDetailProvider);
    }
    ref.invalidate(insightsRepositoryProvider);
    ref.invalidate(homeInsightProvider);
    ref.invalidate(trendOverviewProvider);
    ref.invalidate(trendSeriesProvider);
    ref.invalidate(wellnessRepositoryProvider);
    ref.invalidate(wellnessProvider);
    ref.invalidate(habitTodayProvider);
  }
}

final profileEditorProvider = NotifierProvider<ProfileEditor, AsyncValue<void>>(
  ProfileEditor.new,
);
