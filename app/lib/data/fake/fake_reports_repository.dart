/// In-memory reports. Sample data is clearly fictional and mirrors the
/// mockup so every state can be demonstrated without a backend.
library;

import '../../features/reports/data/report_models.dart';
import '../../features/reports/data/reports_repository.dart';

class FakeReportsRepository implements ReportsRepository {
  FakeReportsRepository({
    this.latency = const Duration(milliseconds: 350),
    this.uploadDelay = const Duration(milliseconds: 1600),
    this.failNextUpload = false,
    List<LabReport>? seed,
  }) : _reports = seed ?? sampleReports();

  final Duration latency;
  final Duration uploadDelay;

  /// Set to make the next upload fail with the mockup's "too blurry" error.
  bool failNextUpload;

  final List<LabReport> _reports;
  int _nextId = 100;

  @override
  Future<List<LabReport>> listReports() async {
    await Future<void>.delayed(latency);
    return List<LabReport>.unmodifiable(_reports);
  }

  @override
  Future<LabReport> getReport(int id) async {
    await Future<void>.delayed(latency);
    return _reports.firstWhere(
      (r) => r.id == id,
      orElse: () => throw const RepositoryException(
        'That report is no longer available.',
        canRetry: false,
      ),
    );
  }

  @override
  Future<LabReport> uploadReport(
    String filePath, {
    ReportLanguage language = ReportLanguage.english,
    void Function(UploadPhase phase)? onPhase,
  }) async {
    final Duration step = uploadDelay ~/ 3;
    onPhase?.call(UploadPhase.uploading);
    await Future<void>.delayed(step);
    onPhase?.call(UploadPhase.reading);
    await Future<void>.delayed(step);
    if (failNextUpload) {
      failNextUpload = false;
      throw const RepositoryException(
        'The image was too blurry to find any values.',
        canRetry: false,
      );
    }
    onPhase?.call(UploadPhase.explaining);
    await Future<void>.delayed(step);
    final LabReport fresh = sampleReports().first.copyWith(
      dateLabel: 'Today',
      date: DateTime.now(),
      language: language,
    );
    final LabReport stored = LabReport(
      id: _nextId++,
      title: fresh.title,
      dateLabel: fresh.dateLabel,
      date: fresh.date,
      status: fresh.status,
      statusText: fresh.statusText,
      attentionCount: fresh.attentionCount,
      summary: fresh.summary,
      values: fresh.values,
      originalText: fresh.originalText,
      simplifiedText: fresh.simplifiedText,
      confidence: 91,
      termsSimplified: 6,
      hasSimplified: true,
      language: language,
    );
    _reports.insert(0, stored);
    return stored;
  }

  /// Mockup sample data. Not a real patient.
  static List<LabReport> sampleReports() => <LabReport>[
    LabReport(
      id: 3,
      title: 'Blood test',
      dateLabel: '18 Oct 2026',
      date: DateTime(2026, 10, 18),
      status: ValueStatus.warn,
      statusText: '2 need attention',
      attentionCount: 2,
      summary:
          'Your blood sugar average is slightly high. Cholesterol and kidney '
          'values look normal.',
      values: const <ReportValue>[
        ReportValue(
          name: 'HbA1c',
          value: '6.4 %',
          status: ValueStatus.warn,
          statusText: 'High',
          explanation:
              'Average blood sugar over 3 months. Above 6.0 is prediabetic '
              'range.',
        ),
        ReportValue(
          name: 'Fasting glucose',
          value: '118 mg/dL',
          status: ValueStatus.warn,
          statusText: 'Slightly high',
          explanation: 'Sugar after fasting. Normal is under 100.',
        ),
        ReportValue(
          name: 'Creatinine',
          value: '0.9 mg/dL',
          status: ValueStatus.ok,
          statusText: 'Normal',
          explanation: 'Shows how well your kidneys filter.',
        ),
        ReportValue(
          name: 'LDL cholesterol',
          value: '92 mg/dL',
          status: ValueStatus.ok,
          statusText: 'Normal',
          explanation: 'The “bad” cholesterol. Lower is better.',
        ),
      ],
      originalText:
          'HbA1c 6.4 % (4.0 - 6.0)\nFasting glucose 118 mg/dL (70 - 100)\n'
          'Creatinine 0.9 mg/dL (0.6 - 1.2)\nLDL cholesterol 92 mg/dL (< 100)',
      simplifiedText:
          'Your average blood sugar over the last 3 months (HbA1c) is 6.4 %, '
          'which is a little above the usual range. Your sugar after fasting '
          'is 118, also slightly high. Your kidney value (creatinine) and '
          'your “bad” cholesterol (LDL) are normal.',
      confidence: 93,
      termsSimplified: 4,
      hasSimplified: true,
    ),
    LabReport(
      id: 2,
      title: 'Lipid profile',
      dateLabel: '12 Aug 2026',
      date: DateTime(2026, 8, 12),
      status: ValueStatus.ok,
      statusText: 'All normal',
      summary: 'All of your cholesterol values are in the normal range.',
      values: const <ReportValue>[
        ReportValue(
          name: 'Total cholesterol',
          value: '168 mg/dL',
          status: ValueStatus.ok,
          statusText: 'Normal',
          explanation: 'All cholesterol added together. Under 200 is good.',
        ),
        ReportValue(
          name: 'HDL cholesterol',
          value: '52 mg/dL',
          status: ValueStatus.ok,
          statusText: 'Normal',
          explanation: 'The “good” cholesterol. Higher is better.',
        ),
      ],
      originalText: 'Total cholesterol 168 mg/dL (< 200)\nHDL 52 mg/dL (> 40)',
      simplifiedText:
          'Your total cholesterol is 168 and your “good” cholesterol (HDL) '
          'is 52. Both are normal.',
      confidence: 95,
      termsSimplified: 2,
      hasSimplified: true,
    ),
    LabReport(
      id: 1,
      title: 'Blood test',
      dateLabel: '2 Jun 2026',
      date: DateTime(2026, 6, 2),
      status: ValueStatus.ok,
      statusText: 'All normal',
      summary: 'Everything on this report is within the normal range.',
      values: const <ReportValue>[
        ReportValue(
          name: 'HbA1c',
          value: '6.1 %',
          status: ValueStatus.ok,
          statusText: 'Normal',
          explanation: 'Average blood sugar over 3 months.',
        ),
      ],
      originalText: 'HbA1c 6.1 % (4.0 - 6.0)',
      simplifiedText:
          'Your average blood sugar over 3 months (HbA1c) is 6.1 %.',
      confidence: 90,
      termsSimplified: 1,
      hasSimplified: true,
    ),
  ];

  static TrendSeries sampleTrend() => const TrendSeries(
    marker: 'HbA1c',
    unit: '%',
    points: <TrendPoint>[
      TrendPoint(label: 'Mar', value: 5.9),
      TrendPoint(label: 'Jun', value: 6.1),
      TrendPoint(label: 'Aug', value: 6.2),
      TrendPoint(label: 'Oct', value: 6.4),
    ],
    threshold: 6.0,
    rangeLabel: '4 reports · Mar to Oct',
    alertTitle: 'Rising 3 times in a row',
    alertBody: 'This isn’t a diagnosis. A doctor can confirm with more tests.',
  );
}
