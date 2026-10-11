/// Thin HTTP wrapper over the MedAIx API.
///
/// HTTP calls for service health and Sprint 1 report upload.
library;

import 'dart:async';
import 'dart:convert';
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
    seconds: int.fromEnvironment('API_HEALTH_TIMEOUT', defaultValue: 30),
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

  /// Total attempts for `/upload-report`, delay between them.
  ///
  /// Mirrors [_healthAttempts]/[_retryDelay] so the report flow survives a cold
  /// Render instance the same way the connectivity probe does. Without this,
  /// the very first upload after the free-tier instance sleeps hits the edge's
  /// bare 502/503 (no FastAPI body) and fails permanently until the user taps
  /// "Try again" by hand — which they cannot distinguish from a broken deploy.
  ///
  /// Retrying a POST is safe here: that edge 5xx is returned *before* the
  /// endpoint runs, so a retry cannot create a duplicate report.
  static const int _uploadAttempts = int.fromEnvironment(
    'API_UPLOAD_ATTEMPTS',
    defaultValue: 3,
  );
  static const Duration _uploadRetryDelay = Duration(seconds: 3);

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

  // ---- Sprint 1: report upload ----

  /// `POST /upload-report`. Returns the extracted text and Tesseract's
  /// confidence in that read.
  ///
  /// [timeout] is long by default: OCR runs synchronously on the server and a
  /// phone photo takes a few seconds to preprocess plus read. The API's own
  /// 30s health budget is not enough headroom for a cold Render instance
  /// booting *and* running OCR, so this gets its own, longer deadline.
  ///
  /// Errors are mapped to user-safe [ApiException]s. The server's `detail`
  /// strings are already written for display (see `main.py`), so they are
  /// surfaced as-is; only transport and format failures get generic wording,
  /// and the raw exception is never shown (§1, §5).
  Future<OcrUploadResult> uploadReport(
    String filePath, {
    String language = 'english',
    Duration timeout = const Duration(seconds: 90),
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _attemptUpload(
          filePath,
          language: language,
          timeout: timeout,
        );
      } on ApiException catch (error) {
        final isLast = attempt >= _uploadAttempts;
        if (isLast || !_isRetryableStatus(error.statusCode)) rethrow;
        await Future<void>.delayed(_uploadRetryDelay);
      }
    }
  }

  /// One upload attempt. A [http.MultipartRequest] body is a single-use
  /// stream, so this rebuilds the request (and re-reads the file) on every
  /// call — the retry loop in [uploadReport] cannot reuse the same object.
  Future<OcrUploadResult> _attemptUpload(
    String filePath, {
    required String language,
    required Duration timeout,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/upload-report'),
    );
    request.fields['language'] = language;

    final file = await File(filePath).readAsBytes();
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        file,
        filename: filePath.split(RegExp(r'[/\\]')).last,
      ),
    );

    try {
      // Streamed rather than .send() so the deadline covers the whole exchange,
      // including the slow upload on a weak connection.
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return OcrUploadResult.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      throw ApiException(
        _detailFrom(response),
        statusCode: response.statusCode,
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(
        'Reading your report took too long. Please try again — '
        'your file has not been lost.',
      );
    } on SocketException catch (error) {
      throw ApiException('Could not reach the MedAIx service.', error: error);
    } on http.ClientException catch (error) {
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

  /// Pull the server's `detail` out of an error body, falling back to a
  /// status-appropriate message when the body is not the expected shape.
  ///
  /// Never surfaces a raw status code: 422 means something different depending
  /// on why it failed, and "422" tells a user nothing actionable.
  String _detailFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['detail'] is String) {
        return body['detail'] as String;
      }
    } on FormatException {
      // Fall through to the generic message below.
    }

    return switch (response.statusCode) {
      413 =>
        'That file is too large to upload. Try a photo of just the report.',
      415 => 'That file type is not supported. Upload a JPEG, PNG, or PDF.',
      422 => 'We could not read that report. Try a clearer photo.',
      503 => 'Report scanning is busy right now. Please try again shortly.',
      _ => 'Something went wrong while reading your report. Please try again.',
    };
  }
}

/// Result of a successful `/upload-report` call.
class OcrUploadResult {
  const OcrUploadResult({
    required this.id,
    required this.text,
    required this.confidence,
    required this.skewCorrectedDegrees,
    required this.language,
  });

  factory OcrUploadResult.fromJson(Map<String, dynamic> json) {
    return OcrUploadResult(
      id: json['id'] as int,
      text: json['text'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      skewCorrectedDegrees:
          (json['skew_corrected_degrees'] as num?)?.toDouble() ?? 0,
      language: json['language'] as String? ?? 'english',
    );
  }

  final int id;
  final String text;
  final double confidence;
  final double skewCorrectedDegrees;
  final String language;

  /// Below this the server would have rejected the upload, so anything that
  /// reaches the success state is at or above the floor. Used only to warn
  /// that a low-but-passing read may be worth re-photographing.
  bool get isLowConfidence => confidence < 60;
}
