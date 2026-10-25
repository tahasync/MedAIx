/// Riverpod providers for cross-cutting state, the report upload flow
/// (Sprint 1), and simplification, report history, and profile (Sprint 2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'auth.dart';

/// Base URL of the MedAIx API. Override at build time:
/// `flutter run --dart-define=API_BASE_URL=https://medaix-api.onrender.com`
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// Theme mode. Dark is the signature experience per the Color System, but the
/// system choice is honoured until Preferences lands in Sprint 13.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setMode(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// Supabase sign-in. Tests override this so widgets never call the network.
final authGatewayProvider = Provider<AuthGateway>(
  (ref) => SupabaseAuthGateway(),
);

/// Current session. Null means the sign-in screen is showing.
class AuthController extends Notifier<AuthSession?> {
  @override
  AuthSession? build() {
    final gateway = ref.watch(authGatewayProvider);
    final subscription = gateway.authStateChanges.listen((session) {
      state = session;
    });
    ref.onDispose(subscription.cancel);
    return gateway.currentSession;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthSession?>(
  AuthController.new,
);

/// HTTP client for API calls, disposed by Riverpod.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: kApiBaseUrl,
    accessToken: () => ref.read(authControllerProvider)?.accessToken,
  );
  ref.onDispose(client.dispose);
  return client;
});

/// OCR mode selected for a report upload.
///
/// Roman Urdu uses the Latin alphabet, so the backend reads it with Tesseract's
/// English model. Urdu script uses Urdu plus English for common lab labels.
enum ReportOcrLanguage {
  english('english', 'English', 'English text'),
  urdu('urdu', 'Urdu', 'Urdu script + English lab labels'),
  romanUrdu('roman_urdu', 'Roman Urdu', 'Urdu written with Latin letters');

  const ReportOcrLanguage(this.apiValue, this.label, this.description);

  final String apiValue;
  final String label;
  final String description;
}

/// Lifecycle of the report-upload flow.
///
/// Modelled as one immutable state rather than several booleans so the screen
/// cannot render "empty" and "error" at the same time — the bug you get from
/// `isLoading`/`hasError`/`isEmpty` flags independently.
sealed class UploadState {
  const UploadState();
}

/// Nothing picked yet. Carries [hasUploadBefore] so the copy can acknowledge
/// that a previous attempt failed rather than pretending this is a first run.
class UploadIdle extends UploadState {
  const UploadIdle({this.hasUploadBefore = false});

  final bool hasUploadBefore;
}

/// File chosen, upload in flight. [fileName] lets the skeleton say what it is
/// working on, so a 10-second wait still feels specific.
class UploadInProgress extends UploadState {
  const UploadInProgress(this.fileName);

  final String fileName;
}

class UploadSuccess extends UploadState {
  const UploadSuccess(this.result);

  final OcrUploadResult result;
}

class UploadFailure extends UploadState {
  const UploadFailure(this.message, {required this.canRetry});

  final String message;

  /// False when the failure is not worth retrying as-is — an unsupported file
  /// type will fail identically forever, and offering "Try again" there just
  /// walks the user into the same wall.
  final bool canRetry;
}

/// Drives `/upload-report`. Keeping the state here rather than in the widget
/// means the flow survives a rebuild and is testable without pumping frames.
class UploadController extends Notifier<UploadState> {
  @override
  UploadState build() => const UploadIdle();

  /// Pick a file and upload it. Safe to call again to retry or replace.
  Future<void> submit(
    String filePath, {
    ReportOcrLanguage language = ReportOcrLanguage.english,
  }) async {
    final fileName = filePath.split(RegExp(r'[/\\]')).last;
    state = UploadInProgress(fileName);

    try {
      final result = await ref
          .read(apiClientProvider)
          .uploadReport(filePath, language: language.apiValue);
      state = UploadSuccess(result);
      // The new report must show up in the history list without a manual
      // refresh, including when that list is still open beneath this screen.
      ref.invalidate(reportsProvider);
    } on ApiException catch (error) {
      // 4xx means the request was understood and refused (wrong file type, no
      // readable text); 5xx and transport failures are worth another go.
      final status = error.statusCode;
      state = UploadFailure(
        error.message,
        canRetry: status == null || status >= 500,
      );
    }
  }

  /// Return to the empty state, e.g. from the success screen's "upload another".
  void reset() => state = const UploadIdle();
}

final uploadControllerProvider =
    NotifierProvider<UploadController, UploadState>(UploadController.new);

/// Lifecycle of the simplify-report flow.
sealed class SimplifyState {
  const SimplifyState();
}

class SimplifyIdle extends SimplifyState {
  const SimplifyIdle();
}

class SimplifyInProgress extends SimplifyState {
  const SimplifyInProgress(this.reportId);
  final int reportId;
}

class SimplifySuccess extends SimplifyState {
  const SimplifySuccess(this.result);
  final SimplifyResult result;
}

class SimplifyFailure extends SimplifyState {
  const SimplifyFailure(
    this.message, {
    required this.reportId,
    required this.canRetry,
  });
  final String message;

  /// Which report failed, so "Try again" can resubmit it.
  final int reportId;

  /// False when the failure is not worth retrying as-is (e.g. a 422), so the
  /// screen doesn't offer a dead-end "Try again".
  final bool canRetry;
}

/// Drives `/simplify-report`. Kept out of the widget so the flow survives a
/// rebuild and can be tested without pumping frames.
class SimplifyController extends Notifier<SimplifyState> {
  @override
  SimplifyState build() => const SimplifyIdle();

  /// Simplify the report with [reportId]. Safe to call again to retry.
  Future<void> submit(int reportId) async {
    state = SimplifyInProgress(reportId);
    try {
      final result = await ref.read(apiClientProvider).simplifyReport(reportId);
      state = SimplifySuccess(result);
    } on ApiException catch (error) {
      // 4xx means the request was understood and refused; 5xx and transport
      // failures are worth another go.
      final status = error.statusCode;
      state = SimplifyFailure(
        error.message,
        reportId: reportId,
        canRetry: status == null || status >= 500,
      );
    }
  }

  /// Return to the empty state, e.g. from "simplify another".
  void reset() => state = const SimplifyIdle();
}

final simplifyControllerProvider =
    NotifierProvider<SimplifyController, SimplifyState>(SimplifyController.new);

/// True after onboarding asks to open the scanner as the first action.
class StartWithUploadController extends Notifier<bool> {
  @override
  bool build() => false;

  void arm() => state = true;

  void consume() => state = false;
}

final startWithUploadProvider =
    NotifierProvider<StartWithUploadController, bool>(
      StartWithUploadController.new,
    );

/// Signed-in patient's profile. Refetches when the session changes.
final profileProvider = FutureProvider<PatientProfile>((ref) async {
  final session = ref.watch(authControllerProvider);
  if (session == null) {
    throw ApiException('Please sign in to continue.');
  }
  return ref.read(apiClientProvider).fetchProfile();
});

/// Stored reports, newest first, for the history screen.
///
/// `autoDispose` so leaving the screen drops the cached list and the next
/// visit fetches fresh data. [UploadController] also invalidates it after a
/// successful upload for the case where the list is still open underneath.
final reportsProvider = FutureProvider.autoDispose<List<ReportSummary>>((
  ref,
) async {
  return await ref.read(apiClientProvider).fetchReports();
});
