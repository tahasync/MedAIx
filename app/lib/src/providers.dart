/// Riverpod providers — Week 0 scaffold.
///
/// Only the cross-cutting app state lives here so far (theme mode + API base
/// URL). Feature providers are added in their own sprint, not ahead of it.
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

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// HTTP client for API calls, disposed by Riverpod.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(baseUrl: kApiBaseUrl);
  ref.onDispose(client.dispose);
  return client;
});