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

  /// Timeout for a connectivity probe.
  ///
  /// Deliberately short: this is a liveness check surfaced directly to the
  /// user, so a hung network must surface as an Error state quickly rather
  /// than leaving a spinner running for the full request budget.
  static const Duration _healthTimeout = Duration(seconds: 10);

  /// `GET /health`. Returns true when the API answers `{"status":"ok"}`.
  ///
  /// Throws [ApiException] with recoverable wording on network failure — the
  /// caller's Error state shows "Try again", never this string.
  ///
  /// Every failure mode maps to [ApiException] so callers need exactly one
  /// `catch`. The `http` package surfaces a refused/reset connection as
  /// [http.ClientException], not a raw [SocketException], and an expired
  /// deadline as [TimeoutException]; both must be handled or the Loading state
  /// never resolves.
  Future<bool> checkHealth() async {
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