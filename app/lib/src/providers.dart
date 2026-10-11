/// Riverpod providers for cross-cutting state and the Sprint 1 upload flow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

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

/// HTTP client for API calls, disposed by Riverpod.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(baseUrl: kApiBaseUrl);
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
