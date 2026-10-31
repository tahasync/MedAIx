/// FastAPI-backed repositories. Thin adapters over [ApiClient] that map the
/// wire models onto the domain models the screens use, and [ApiException]
/// onto [RepositoryException].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../features/profile/data/profile_repository.dart';
import '../../features/reports/data/lab_value_parser.dart';
import '../../features/reports/data/report_models.dart';
import '../../features/reports/data/reports_repository.dart';
import 'api_client.dart';

class ApiReportsRepository implements ReportsRepository {
  ApiReportsRepository(this._api);

  final ApiClient _api;

  /// Upload dates by id, filled by [listReports] so [getReport] can label a
  /// report without a second round-trip when the list was seen first.
  final Map<int, String> _dates = <int, String>{};
  final Map<int, String> _titles = <int, String>{};
  final Map<int, String> _parseNotes = <int, String>{};

  @override
  Future<void> clearHealthData() async {
    _dates.clear();
    _titles.clear();
    _parseNotes.clear();
  }

  @override
  Future<List<LabReport>> listReports() => _guard(() async {
    final List<ReportSummary> rows = await _api.fetchReports();
    return rows.map((row) {
      final String date = formatReportDate(row.reportDate ?? row.uploadedAt);
      _dates[row.id] = date;
      _titles[row.id] = row.title;
      if (row.parseNote != null) _parseNotes[row.id] = row.parseNote!;
      final int attention = row.attentionCount;
      final (ValueStatus status, String statusText) = !row.hasSimplified
          ? (ValueStatus.neutral, 'Not explained yet')
          : attention == 0
          ? (ValueStatus.ok, 'All normal')
          : (
              ValueStatus.warn,
              attention == 1
                  ? '1 needs attention'
                  : '$attention need attention',
            );
      return LabReport(
        id: row.id,
        title: row.title,
        dateLabel: date,
        date: DateTime.tryParse(row.reportDate ?? row.uploadedAt),
        status: status,
        statusText: statusText,
        attentionCount: attention,
        confidence: row.confidence,
        hasSimplified: row.hasSimplified,
        parseNote: row.parseNote,
      );
    }).toList();
  });

  @override
  Future<LabReport> uploadReport(
    String filePath, {
    ReportLanguage language = ReportLanguage.english,
    String? uploadId,
    void Function(UploadPhase phase)? onPhase,
  }) => _guard(() async {
    onPhase?.call(UploadPhase.uploading);
    final OcrUploadResult ocr = await _api.uploadReport(
      filePath,
      language: language.apiValue,
      uploadId: uploadId,
    );
    onPhase?.call(UploadPhase.explaining);
    _dates[ocr.id] = 'Today';
    late final SimplifyResult simplified;
    try {
      simplified = await _api.simplifyReport(ocr.id);
    } on ApiException {
      // OCR upload already committed the report. Keep it reachable in the
      // history and navigate to its detail, where the idempotent explain call
      // can be retried without uploading the same file a second time.
      return _fromOcr(
        ocr,
        dateLabel: 'Today',
        date: DateTime.now(),
        language: language,
      );
    }
    return _detail(
      simplified,
      dateLabel: 'Today',
      date: DateTime.now(),
      confidence: ocr.confidence,
      language: language,
    );
  });

  LabReport _fromOcr(
    OcrUploadResult result, {
    required String dateLabel,
    required DateTime date,
    required ReportLanguage language,
  }) {
    final List<ReportValue> values = parseLabValues(result.text);
    final int attention = values
        .where(
          (value) =>
              value.status == ValueStatus.warn ||
              value.status == ValueStatus.error,
        )
        .length;
    final (ValueStatus status, String statusText) = values.isEmpty
        ? (ValueStatus.neutral, 'Explanation pending')
        : attention == 0
        ? (ValueStatus.ok, 'All normal')
        : (
            ValueStatus.warn,
            attention == 1 ? '1 needs attention' : '$attention need attention',
          );
    return LabReport(
      id: result.id,
      title: guessReportTitle(result.text),
      dateLabel: dateLabel,
      date: date,
      status: status,
      statusText: statusText,
      attentionCount: attention,
      values: values,
      originalText: result.text,
      confidence: result.confidence,
      hasSimplified: false,
      language: language,
    );
  }

  @override
  Future<LabReport> getReport(int id) => _guard(() async {
    // `/simplify-report` is idempotent: a second call returns the stored
    // text, so it doubles as "fetch detail".
    final SimplifyResult simplified = await _api.simplifyReport(id);
    String? date = _dates[id];
    try {
      // Refresh parse coverage too: the deterministic OCR parser may have
      // improved since this report was uploaded, while the in-memory list
      // cache still holds the older counts.
      await listReports();
      date = _dates[id] ?? date;
    } on RepositoryException {
      // The detail is still useful without refreshed list metadata.
    }
    return _detail(simplified, dateLabel: date ?? 'Report $id');
  });

  LabReport _detail(
    SimplifyResult r, {
    required String dateLabel,
    DateTime? date,
    double? confidence,
    ReportLanguage language = ReportLanguage.english,
  }) {
    final List<ReportValue> values = parseLabValues(r.originalText);
    final int attention = values
        .where(
          (v) => v.status == ValueStatus.warn || v.status == ValueStatus.error,
        )
        .length;
    final (ValueStatus status, String statusText) = values.isEmpty
        ? (ValueStatus.ok, 'Ready to read')
        : attention == 0
        ? (ValueStatus.ok, 'All normal')
        : (
            ValueStatus.warn,
            attention == 1 ? '1 needs attention' : '$attention need attention',
          );
    return LabReport(
      id: r.id,
      title: _titles[r.id] ?? guessReportTitle(r.originalText),
      dateLabel: dateLabel,
      date: date,
      status: status,
      statusText: statusText,
      attentionCount: attention,
      summary: leadSentences(r.simplifiedText),
      values: values,
      originalText: r.originalText,
      simplifiedText: r.simplifiedText,
      confidence: confidence,
      termsSimplified: r.termsSimplified,
      hasSimplified: true,
      language: language,
      parseNote: _parseNotes[r.id],
    );
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on ApiException catch (error) {
      final int? status = error.statusCode;
      throw RepositoryException(
        error.message,
        canRetry: status == null || status >= 500,
        cause: error,
      );
    }
  }
}

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository(this._api, {http.Client? client})
    : _client = client ?? http.Client();

  final ApiClient _api;

  /// Used for the partial `PUT /profile` (Sprint 3 contract), which sends
  /// only the fields a draft sets. [ApiClient.saveProfile] still speaks the
  /// older all-required shape, so the request is built here.
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 30);

  @override
  Future<PatientProfile> fetch() => _guard(_api.fetchProfile);

  @override
  Future<PatientProfile> save(ProfileDraft d) => _guard(() => _put(d.toJson()));

  @override
  Future<void> delete() => _guard(_api.deleteProfile);

  Future<PatientProfile> _put(Map<String, dynamic> body) async {
    const String fallback = 'Could not save your profile. Please try again.';
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final String? token = _api.accessToken?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    try {
      final http.Response response = await _client
          .put(
            Uri.parse('${_api.baseUrl}/profile'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return PatientProfile.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      throw ApiException(
        _detail(response, fallback),
        statusCode: response.statusCode,
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(fallback);
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

  /// The server's `detail` is written for display (the 422 messages in the
  /// contract are shown verbatim); anything else gets [fallback].
  static String _detail(http.Response response, String fallback) {
    try {
      final Object? body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['detail'] is String) {
        return body['detail'] as String;
      }
    } on FormatException {
      // Fall through.
    }
    return response.statusCode == 401
        ? 'Please sign in to continue.'
        : fallback;
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on ApiException catch (error) {
      final int? status = error.statusCode;
      throw RepositoryException(
        error.message,
        canRetry: status == null || status >= 500,
        cause: error,
      );
    }
  }
}

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "2026-10-18" or "2026-10-18T09:12:00" → "18 Oct 2026". Date-only strings
/// are not shifted into local time (that would move the day near UTC±12).
String formatReportDate(String iso) {
  if (iso.length >= 10) {
    final List<String> parts = iso.substring(0, 10).split('-');
    if (parts.length == 3) {
      final int? year = int.tryParse(parts[0]);
      final int? month = int.tryParse(parts[1]);
      final int? day = int.tryParse(parts[2]);
      if (year != null &&
          month != null &&
          day != null &&
          month >= 1 &&
          month <= 12) {
        return '$day ${_months[month - 1]} $year';
      }
    }
  }
  return iso;
}
