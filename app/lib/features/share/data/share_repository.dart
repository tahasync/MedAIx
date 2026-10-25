/// Time-limited, read-only sharing with a doctor, and the doctor's view.
library;

class ShareSession {
  const ShareSession({
    required this.code,
    required this.minutes,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Opaque code the QR encodes. Also seeds the QR pattern.
  final String code;
  final int minutes;
  final DateTime createdAt;
  final DateTime expiresAt;

  Duration remaining(DateTime now) {
    final Duration left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  /// Deterministic seed for the QR drawing.
  int get seed =>
      code.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);
}

/// One record visible to the doctor.
class SharedRecord {
  const SharedRecord({required this.kind, required this.title});

  final SharedRecordKind kind;
  final String title;
}

enum SharedRecordKind { report, medicines }

/// What the doctor sees after scanning.
class DoctorPortalView {
  const DoctorPortalView({
    required this.patientName,
    required this.summary,
    required this.records,
    required this.expiresAt,
  });

  final String patientName;

  /// e.g. "Diabetes · Peanut allergy".
  final String summary;
  final List<SharedRecord> records;
  final DateTime expiresAt;
}

abstract class ShareRepository {
  /// The current session, or null when there is no active code.
  Future<ShareSession?> active();

  Future<ShareSession> create({required int minutes});

  Future<void> revoke();

  /// The read-only view for [code]. Throws when the code is unknown or
  /// expired.
  Future<DoctorPortalView> portalView(String code);
}

/// Formats a remaining duration as mm:ss.
String formatCountdown(Duration d) {
  final int total = d.inSeconds.clamp(0, 359999);
  final int minutes = total ~/ 60;
  final int seconds = total % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
