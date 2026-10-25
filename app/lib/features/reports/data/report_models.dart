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
  const TrendPoint({required this.label, required this.value});

  /// Short x label, e.g. "Mar".
  final String label;
  final double value;
}

/// A marker's history plus the threshold and the alert copy that goes with
/// it. `null` from the repository means there is not enough data yet.
class TrendSeries {
  const TrendSeries({
    required this.marker,
    required this.unit,
    required this.points,
    required this.threshold,
    required this.rangeLabel,
    this.alertTitle,
    this.alertBody,
  });

  final String marker;
  final String unit;
  final List<TrendPoint> points;

  /// Dashed line value.
  final double threshold;

  /// e.g. "4 reports · Mar to Oct".
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
    return '$marker $verb from ${first.value} to ${last.value} '
        'over ${points.length} reports.';
  }
}

/// Progress of an upload, for the reading screen's bar.
enum UploadPhase { uploading, reading, explaining }

extension UploadPhaseX on UploadPhase {
  double get progress => switch (this) {
    UploadPhase.uploading => 0.25,
    UploadPhase.reading => 0.62,
    UploadPhase.explaining => 0.9,
  };

  String get label => switch (this) {
    UploadPhase.uploading => 'Step 1 of 3 · uploading',
    UploadPhase.reading => 'Step 2 of 3 · extracting values',
    UploadPhase.explaining => 'Step 3 of 3 · explaining',
  };
}
