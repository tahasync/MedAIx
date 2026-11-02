/// Typed response models returned by the MedAIx API.
library;

/// Result of a successful `/upload-report` call.
class OcrUploadResult {
  const OcrUploadResult({
    required this.id,
    required this.text,
    required this.confidence,
    required this.skewCorrectedDegrees,
    required this.language,
    this.statusCode,
    this.statusText,
    this.duplicate = false,
  });

  factory OcrUploadResult.fromJson(Map<String, dynamic> json) {
    return OcrUploadResult(
      id: json['id'] as int,
      text: json['text'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      skewCorrectedDegrees:
          (json['skew_corrected_degrees'] as num?)?.toDouble() ?? 0,
      language: json['language'] as String? ?? 'english',
      statusCode: json['status_code'] as String?,
      statusText: json['status_text'] as String?,
      duplicate: json['duplicate'] as bool? ?? false,
    );
  }

  final int id;
  final String text;
  final double confidence;
  final double skewCorrectedDegrees;
  final String language;
  final String? statusCode;
  final String? statusText;
  final bool duplicate;

  /// Below this the server would have rejected the upload, so anything that
  /// reaches the success state is at or above the floor. Used only to warn
  /// that a low-but-passing read may be worth re-photographing.
  bool get isLowConfidence => confidence < 60;
}

/// Result of a successful `/simplify-report` call.
class SimplifyResult {
  const SimplifyResult({
    required this.id,
    required this.originalText,
    required this.simplifiedText,
    this.termsSimplified,
    this.sentenceCount,
    required this.note,
    this.statusCode,
    this.statusText,
  });

  factory SimplifyResult.fromJson(Map<String, dynamic> json) {
    return SimplifyResult(
      id: json['id'] as int,
      originalText: json['original_text'] as String? ?? '',
      simplifiedText: json['simplified_text'] as String? ?? '',
      termsSimplified: (json['terms_simplified'] as num?)?.toInt(),
      sentenceCount: (json['sentence_count'] as num?)?.toInt(),
      note: json['note'] as String? ?? '',
      statusCode: json['status_code'] as String?,
      statusText: json['status_text'] as String?,
    );
  }

  final int id;
  final String originalText;
  final String simplifiedText;
  final int? termsSimplified;
  final int? sentenceCount;
  final String note;
  final String? statusCode;
  final String? statusText;
}

/// One row from `GET /reports`, used by the report-history screen.
class ReportSummary {
  const ReportSummary({
    required this.id,
    required this.uploadedAt,
    required this.confidence,
    required this.hasSimplified,
    required this.imagePath,
    this.title = 'Lab report',
    this.reportDate,
    this.attentionCount = 0,
    this.valuesRead,
    this.valuesExpected,
    this.parseNote,
    this.statusCode,
    this.statusText,
  });

  factory ReportSummary.fromJson(Map<String, dynamic> json) {
    return ReportSummary(
      id: json['id'] as int,
      uploadedAt: json['uploaded_at'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      hasSimplified: json['has_simplified'] as bool? ?? false,
      imagePath: json['image_path'] as String? ?? '',
      title: json['title'] as String? ?? 'Lab report',
      reportDate: json['report_date'] as String?,
      attentionCount: (json['attention_count'] as num?)?.toInt() ?? 0,
      valuesRead: (json['values_read'] as num?)?.toInt(),
      valuesExpected: (json['values_expected'] as num?)?.toInt(),
      parseNote: json['parse_note'] as String?,
      statusCode: json['status_code'] as String?,
      statusText: json['status_text'] as String?,
    );
  }

  final int id;
  final String uploadedAt;
  final double confidence;
  final bool hasSimplified;
  final String imagePath;
  final String title;
  final String? reportDate;
  final int attentionCount;
  final int? valuesRead;
  final int? valuesExpected;
  final String? parseNote;
  final String? statusCode;
  final String? statusText;
}
