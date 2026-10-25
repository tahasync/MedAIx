/// Repository wiring. Screens only ever read these providers; tests override
/// them with fakes so no widget test touches the network.
///
/// Reports, profile and insights/trends are backed by the FastAPI service
/// once signed in (Sprints 1–3 are real). Everything else (meds, wellness,
/// sharing, doctor match) is an in-memory fake until the backend grows those
/// endpoints. `--dart-define=MEDAIX_FAKE_DATA=true` switches the real ones to
/// fakes too, for demos without a server.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/auth_gateway.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/doctor/data/doctor_repository.dart';
import '../features/home/data/insights_repository.dart';
import '../features/meds/data/meds_repository.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/reports/data/reports_repository.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/share/data/share_repository.dart';
import '../features/wellness/data/wellness_repository.dart';
import '../features/wellness/data/api_wellness_repository.dart';
import 'api/api_client.dart';
import 'api/api_insights_repository.dart';
import 'api/api_repositories.dart';
import 'fake/fake_repositories.dart';
import 'prefs/prefs_settings_repository.dart';

/// Base URL of the MedAIx API. Override at build time:
/// `flutter run --dart-define=API_BASE_URL=https://medaix-api.onrender.com`
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// Demo mode: every repository is a fake, no server needed.
const bool kUseFakeData = bool.fromEnvironment('MEDAIX_FAKE_DATA');

/// HTTP client for API calls, disposed by Riverpod.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: kApiBaseUrl,
    accessToken: () => ref.read(authControllerProvider)?.accessToken,
  );
  ref.onDispose(client.dispose);
  return client;
});

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  if (kUseFakeData) return FakeReportsRepository();
  return ApiReportsRepository(ref.watch(apiClientProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (kUseFakeData) {
    final AuthSession? session = ref.watch(authControllerProvider);
    return FakeProfileRepository(
      seed: PatientProfile(id: 1, name: session?.email?.split('@').first),
    );
  }
  return ApiProfileRepository(ref.watch(apiClientProvider));
});

final medsRepositoryProvider = Provider<MedsRepository>(
  (ref) => FakeMedsRepository(),
);

final wellnessRepositoryProvider = Provider<WellnessRepository>((ref) {
  if (kUseFakeData) return FakeWellnessRepository();
  final AuthSession? session = ref.watch(authControllerProvider);
  return ApiWellnessRepository(
    ref.watch(apiClientProvider),
    userId: session?.userId ?? 'signed-out',
  );
});

final shareRepositoryProvider = Provider<ShareRepository>(
  (ref) => FakeShareRepository(),
);

final doctorRepositoryProvider = Provider<DoctorRepository>(
  (ref) => FakeDoctorRepository(),
);

/// Sprint 3: insights and trends come from `GET /risk-trends`.
final insightsRepositoryProvider = Provider<InsightsRepository>((ref) {
  if (kUseFakeData) return FakeInsightsRepository();
  return ApiInsightsRepository(ref.watch(apiClientProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => PrefsSettingsRepository(),
);
