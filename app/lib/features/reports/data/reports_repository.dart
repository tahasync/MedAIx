/// Repository interface for lab reports. The UI depends only on this; the
/// in-memory fake and the FastAPI-backed implementation are swapped in
/// `lib/data/repositories.dart`.
library;

import 'report_models.dart';

/// Thrown by repositories with a message already written for display.
/// Screens show [message] and a recovery action; never the raw cause.
class RepositoryException implements Exception {
  const RepositoryException(this.message, {this.canRetry = true, this.cause});

  final String message;

  /// False when retrying as-is would fail identically (unsupported file,
  /// unreadable photo), so screens offer "Choose another file" instead of a
  /// dead-end "Try again".
  final bool canRetry;
  final Object? cause;

  @override
  String toString() => 'RepositoryException: $message';
}

abstract class ReportsRepository {
  /// Newest first. Summary fields only.
  Future<List<LabReport>> listReports();

  /// Clear report data kept in this repository after profile health-data
  /// deletion. The API already deletes its rows in that request.
  Future<void> clearHealthData();

  /// Uploads a photo/PDF, reads it, and explains it. [onPhase] is called as
  /// the work progresses so the reading screen can move its bar.
  Future<LabReport> uploadReport(
    String filePath, {
    ReportLanguage language = ReportLanguage.english,
    String? uploadId,
    void Function(UploadPhase phase)? onPhase,
  });

  /// Full report: summary, values, original and simplified text.
  Future<LabReport> getReport(int id);
}
