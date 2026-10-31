/// Report domain models shared by the UI and both repository
/// implementations (fake and FastAPI-backed).
library;

import '../../../core/widgets/chips_and_status.dart';

export '../../../core/widgets/chips_and_status.dart' show ValueStatus;

/// OCR mode selected for an upload. Roman Urdu uses the Latin alphabet, so
/// the backend reads it with the English model; Urdu script uses Urdu plus
/// English for common lab labels.
enum ReportLanguage {
  english('english', 'English', 'English text'),
  urdu('urdu', 'Urdu', 'Urdu script + English lab labels'),
  romanUrdu('roman_urdu', 'Roman Urdu', 'Urdu written with Latin letters');

  const ReportLanguage(this.apiValue, this.label, this.description);

  final String apiValue;
  final String label;
  final String description;
}

/// One measured value on a report, already judged against its range.
class ReportValue {
  const ReportValue({
    required this.name,
    required this.value,
    required this.status,
    required this.statusText,
    required this.explanation,
  });

  /// e.g. "HbA1c".
  final String name;

  /// Display value with unit, e.g. "6.4 %".
  final String value;
  final ValueStatus status;

  /// The word next to the status icon: "High", "Slightly high", "Normal".
  final String statusText;

  /// One plain-language line.
  final String explanation;
}

/// A stored report. Lists carry the summary fields; [values], [summary]
/// and the texts are filled by `getReport`.
class LabReport {
  const LabReport({
    required this.id,
    required this.title,
    required this.dateLabel,
    required this.status,
    required this.statusText,
    this.date,
    this.attentionCount = 0,
    this.summary = '',
    this.values = const <ReportValue>[],
    this.originalText = '',
    this.simplifiedText = '',
    this.confidence,
    this.termsSimplified,
    this.hasSimplified = false,
    this.language = ReportLanguage.english,
    this.parseNote,
  });

  final int id;

  /// e.g. "Blood test".
  final String title;

  /// e.g. "18 Oct 2026".
  final String dateLabel;
  final DateTime? date;

  /// Overall status and its word: "2 need attention" / "All normal" /
  /// "Ready to read".
  final ValueStatus status;
  final String statusText;
  final int attentionCount;

  /// "In plain words" paragraph.
  final String summary;
  final List<ReportValue> values;

  /// Full OCR text and its plain-language rewrite.
  final String originalText;
  final String simplifiedText;

  /// OCR confidence 0–100, when known.
  final double? confidence;
  final int? termsSimplified;
  final bool hasSimplified;
  final ReportLanguage language;

  /// Set when the parser recovered only some of the printed rows, e.g.
  /// "We read 4 of 9 values". The original photo stays the source of truth.
  final String? parseNote;

  bool get hasValues => values.isNotEmpty;

  LabReport copyWith({
    String? title,
    String? dateLabel,
    DateTime? date,
    ValueStatus? status,
    String? statusText,
    int? attentionCount,
    String? summary,
    List<ReportValue>? values,
    String? originalText,
    String? simplifiedText,
    double? confidence,
    int? termsSimplified,
    bool? hasSimplified,
    ReportLanguage? language,
    String? parseNote,
  }) {
    return LabReport(
      id: id,
      title: title ?? this.title,
      dateLabel: dateLabel ?? this.dateLabel,
      date: date ?? this.date,
      status: status ?? this.status,
      statusText: statusText ?? this.statusText,
      attentionCount: attentionCount ?? this.attentionCount,
      summary: summary ?? this.summary,
      values: values ?? this.values,
      originalText: originalText ?? this.originalText,
      simplifiedText: simplifiedText ?? this.simplifiedText,
      confidence: confidence ?? this.confidence,
      termsSimplified: termsSimplified ?? this.termsSimplified,
      hasSimplified: hasSimplified ?? this.hasSimplified,
      language: language ?? this.language,
      parseNote: parseNote ?? this.parseNote,
    );
  }
}

/// A point on a trend chart.
class TrendPoint {
  const TrendPoint({
    required this.date,
    required this.dateSource,
    required this.value,
  });

  final DateTime date;

  /// `report`, `upload`, or `sample` for obviously synthetic fixtures.
  final String dateSource;
  final double value;
}

/// A marker's history plus the threshold and the alert copy that goes with
/// it. `null` from the repository means there is not enough data yet.
class TrendSeries {
  const TrendSeries({
    required this.marker,
    required this.unit,
    required this.points,
    this.threshold,
    required this.rangeLabel,
    this.alertTitle,
    this.alertBody,
  });

  final String marker;
  final String unit;
  final List<TrendPoint> points;

  /// A real reference boundary, when one exists.
  final double? threshold;

  /// Count and actual date span.
  final String rangeLabel;
  final String? alertTitle;
  final String? alertBody;

  /// Screen-reader description of the whole chart.
  String get semanticDescription {
    if (points.isEmpty) return '$marker trend. No data yet.';
    final first = points.first;
    final last = points.last;
    final verb = last.value > first.value
        ? 'rose'
        : last.value < first.value
        ? 'fell'
        : 'stayed';
    final String firstSource = first.dateSource == 'report'
        ? 'report date'
        : first.dateSource == 'sample'
        ? 'sample date'
        : 'upload date';
    final String lastSource = last.dateSource == 'report'
        ? 'report date'
        : last.dateSource == 'sample'
        ? 'sample date'
        : 'upload date';
    return '$marker $verb from ${first.value} on ${_trendDate(first.date)} '
        '($firstSource) to ${last.value} on ${_trendDate(last.date)} '
        '($lastSource), across ${points.length} reports.';
  }
}

String _trendDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Progress of an upload, for the reading screen's bar.
enum UploadPhase { uploading, reading, explaining }

extension UploadPhaseX on UploadPhase {
  String get label => switch (this) {
    UploadPhase.uploading => 'Sending the report and reading its text',
    UploadPhase.reading => 'Checking the values we could read',
    UploadPhase.explaining => 'Preparing a plain language explanation',
  };

  String get title => switch (this) {
    UploadPhase.uploading => 'Reading your report',
    UploadPhase.reading => 'Checking report values',
    UploadPhase.explaining => 'Preparing your explanation',
  };
}
