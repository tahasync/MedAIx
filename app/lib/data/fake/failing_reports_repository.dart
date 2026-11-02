/// Fake repository implementation isolated by feature responsibility.
library;

import '../../features/reports/data/report_models.dart';
import '../../features/reports/data/reports_repository.dart';

/// Synthetic in-memory implementation for tests and local demos.
class FailingReportsRepository implements ReportsRepository {
  const FailingReportsRepository([
    this.message = 'Could not reach the MedAIx service.',
  ]);

  final String message;

  @override
  Future<void> clearHealthData() async {}

  @override
  Future<List<LabReport>> listReports() async =>
      throw RepositoryException(message);

  @override
  Future<LabReport> getReport(int id) async =>
      throw RepositoryException(message);

  @override
  Future<LabReport> uploadReport(
    String filePath, {
    ReportLanguage language = ReportLanguage.english,
    String? uploadId,
    void Function(UploadPhase phase)? onPhase,
  }) async => throw RepositoryException(message);
}
