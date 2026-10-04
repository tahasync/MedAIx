/// Thin HTTP wrapper over the MedAIx API.
///
/// Deliberately small at Week 0: it exists so `/health` can be verified against
/// a real backend. Feature calls arrive with their sprint.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Raised for any non-success response.
///
/// [message] is already user-safe plain language — callers must not surface
/// [error] (the raw cause) directly in the UI (§1, §5).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.error});

  final String message;
  final int? statusCode;
  final Object? error;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// Timeout for a single connectivity attempt.
  ///
  /// Overridable at build time:
  /// `flutter run --dart-define=API_HEALTH_TIMEOUT=30`
  ///
  /// The default is 30s rather than a tight budget because the API may be
  /// hosted on Render's free tier, which spins the instance down after ~15
  /// idle minutes. The first request after a wake has to boot Python and load
  /// FastAPI before it can answer, and a short timeout would report that
  /// perfectly healthy backend as unreachable. This is still bounded: a dead
  /// host fails fast on connection refused, and this deadline only governs how
  /// long we wait on a *slow* one.
  static const Duration _healthTimeout = Duration(
    seconds: int.fromEnvironment(
      'API_HEALTH_TIMEOUT',
      defaultValue: 30,
    ),
  );

  /// Extra attempts after a transient failure.
  ///
  /// A cold Render instance answers with a slow/5xx response rather than a
  /// clean error, so a single failed probe says nothing about whether the
  /// backend is reachable. Retrying absorbs the wake-up without making the
  /// user press "Try again" by hand — which matters because the person who
  /// taps that button usually cannot tell a sleeping instance from a broken
  /// deployment.
  static const int _healthAttempts = int.fromEnvironment(
    'API_HEALTH_ATTEMPTS',
    defaultValue: 3,
  );

  /// Pause between attempts. Long enough not to hammer a booting instance,
  /// short enough that the total stays tolerable.
  static const Duration _retryDelay = Duration(seconds: 2);

  /// Status codes worth retrying: Render's edge returns 502/503 while an
  /// instance is booting. A 4xx is a real answer and is surfaced immediately.
  static bool _isRetryableStatus(int? statusCode) =>
      statusCode == null || statusCode >= 500;

  /// `GET /health`. Returns true when the API answers `{"status":"ok"}`.
  ///
  /// Retries a transient failure (timeout, connection reset, 5xx) up to
  /// [_healthAttempts] times so a sleeping free-tier instance has a chance to
  /// wake, then throws [ApiException] with recoverable wording on network
  /// failure — the caller's Error state shows "Try again", never this string.
  ///
  /// A 4xx is not retried: the service answered, and it answered "no".
  Future<bool> checkHealth() async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _attemptHealth();
      } on ApiException catch (error) {
        final isLast = attempt >= _healthAttempts;
        if (isLast || !_isRetryableStatus(error.statusCode)) rethrow;
        await Future<void>.delayed(_retryDelay);
      }
    }
  }

  /// One health request. Every failure mode maps to [ApiException] so callers
  /// need exactly one `catch`. The `http` package surfaces a refused/reset
  /// connection as [http.ClientException], not a raw [SocketException], and an
  /// expired deadline as [TimeoutException]; both must be handled or the
  /// Loading state never resolves.
  Future<bool> _attemptHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(_healthTimeout);

      if (response.statusCode != 200) {
        throw ApiException(
          'The health check did not succeed.',
          statusCode: response.statusCode,
        );
      }

      return response.body.contains('"ok"');
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('The MedAIx service took too long to respond.');
    } on SocketException catch (error) {
      throw ApiException('Could not reach the MedAIx service.', error: error);
    } on http.ClientException catch (error) {
      // Covers connection refused/reset and TLS failures, which the client
      // wraps rather than delivering as SocketException.
      throw ApiException('Could not reach the MedAIx service.', error: error);
    } on HttpException catch (error) {
      throw ApiException(
        'The connection to MedAIx was interrupted.',
        error: error,
      );
    } on FormatException catch (error) {
      throw ApiException(
        'The service returned an unexpected response.',
        error: error,
      );
    }
  }

  void dispose() => _client.close();
}