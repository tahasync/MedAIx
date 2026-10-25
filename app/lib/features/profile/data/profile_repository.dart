/// The signed-in patient's profile and health details.
///
/// Mirrors the Sprint 3 contract for `GET /profile` / `PUT /profile`
/// (`docs/questionnaire.md`, "Profile fields produced"). Field names and enum
/// values on the wire are fixed by that contract.
library;

/// The two consents from Screen 1 of the questionnaire, as stored by the
/// server (which stamps [version] and [acceptedAt]).
class ProfileConsent {
  const ProfileConsent({
    required this.terms,
    required this.healthData,
    this.version,
    this.acceptedAt,
  });

  factory ProfileConsent.fromJson(Map<String, dynamic> json) {
    return ProfileConsent(
      terms: json['terms'] as bool? ?? false,
      healthData: json['health_data'] as bool? ?? false,
      version: json['version'] as String?,
      acceptedAt: _parseDateTime(json['accepted_at']),
    );
  }

  final bool terms;
  final bool healthData;
  final String? version;
  final DateTime? acceptedAt;

  /// Both switches were turned on.
  bool get complete => terms && healthData;

  /// What `PUT /profile` accepts: only `true` values, no stamps.
  static const Map<String, dynamic> grantJson = <String, dynamic>{
    'terms': true,
    'health_data': true,
  };
}

/// Mirrors `GET /profile`. Free-text lists are comma separated strings on
/// the wire; [conditionList] etc. split them for chips.
class PatientProfile {
  const PatientProfile({
    required this.id,
    this.name,
    this.email,
    this.dateOfBirth,
    this.age,
    this.sexAtBirth,
    this.consent,
    this.conditions = '',
    this.allergies = '',
    this.takesMedicines,
    this.medications = '',
    this.pregnancyStatus,
    this.prostateUrinaryIssue,
    this.firstGoal,
    this.heightCm,
    this.weightKg,
    this.onboardingComplete = false,
  });

  factory PatientProfile.fromJson(Map<String, dynamic> json) {
    final DateTime? dob = _parseDate(json['date_of_birth']);
    final Map<String, dynamic>? consent =
        json['consent'] as Map<String, dynamic>?;
    return PatientProfile(
      id: json['id'] as int,
      name: json['name'] as String?,
      email: json['email'] as String?,
      dateOfBirth: dob,
      age: (json['age'] as num?)?.toInt() ?? (dob == null ? null : ageAt(dob)),
      sexAtBirth: normalizeSex(
        json['sex_at_birth'] as String? ?? json['sex'] as String?,
      ),
      consent: consent == null ? null : ProfileConsent.fromJson(consent),
      conditions: json['conditions'] as String? ?? '',
      allergies: json['allergies'] as String? ?? '',
      takesMedicines: json['takes_medicines'] as bool?,
      medications: json['medications'] as String? ?? '',
      pregnancyStatus: _lower(json['pregnancy_status'] as String?),
      prostateUrinaryIssue: _lower(json['prostate_urinary_issue'] as String?),
      firstGoal: _lower(json['first_goal'] as String?),
      heightCm: ((json['height_cm'] ?? json['height']) as num?)?.toDouble(),
      weightKg: ((json['weight_kg'] ?? json['weight']) as num?)?.toDouble(),
      onboardingComplete: json['onboarding_complete'] as bool? ?? false,
    );
  }

  final int id;
  final String? name;
  final String? email;
  final DateTime? dateOfBirth;

  /// Derived from [dateOfBirth] by the server; a legacy value when there is
  /// no date of birth.
  final int? age;

  /// `female` | `male` | `prefer_not_to_say` | null.
  final String? sexAtBirth;
  final ProfileConsent? consent;
  final String conditions;
  final String allergies;

  /// true | false | null (not answered).
  final bool? takesMedicines;
  final String medications;

  /// Female only: `no` | `pregnant` | `breastfeeding` | `prefer_not_to_say`.
  final String? pregnancyStatus;

  /// Male 40+ only: `no` | `yes` | `prefer_not_to_say`.
  final String? prostateUrinaryIssue;

  /// `reports` | `medicines` | `condition` | `habits` | null.
  final String? firstGoal;
  final double? heightCm;
  final double? weightKg;
  final bool onboardingComplete;

  // Legacy aliases kept so older call sites keep compiling.
  String? get sex => sexAtBirth;
  double? get height => heightCm;
  double? get weight => weightKg;

  List<String> get conditionList => _split(conditions);
  List<String> get medicationList => _split(medications);
  List<String> get allergyList => _split(allergies);

  /// Screen 1 of the questionnaire is on file: date of birth, sex at birth
  /// and both consents. The server's `onboarding_complete` also needs a name.
  bool get hasAccountBasics =>
      dateOfBirth != null && sexAtBirth != null && (consent?.complete ?? false);

  /// Whether the "pregnant or breastfeeding" question applies (2.4F).
  bool get asksPregnancy => sexAtBirth == 'female';

  /// Whether the "prostate or urinary problems" question applies (2.4M).
  bool get asksProstate => sexAtBirth == 'male' && (age ?? 0) >= 40;

  static List<String> _split(String raw) => raw
      .split(RegExp(r'[,;\n]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  static String join(Iterable<String> items) =>
      items.map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');

  /// Full years between [dob] and [today] (defaults to now).
  static int ageAt(DateTime dob, {DateTime? today}) {
    final DateTime now = today ?? DateTime.now();
    int years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years;
  }

  /// Wire values are lower case; the legacy `other` maps to the new
  /// `prefer_not_to_say`.
  static String? normalizeSex(String? raw) {
    final String? value = _lower(raw);
    if (value == null) return null;
    return value == 'other' ? 'prefer_not_to_say' : value;
  }

  String get displayName {
    final n = name?.trim();
    return n == null || n.isEmpty ? 'there' : n;
  }

  /// Applies [draft] the way the server would (used by the in-memory fake).
  PatientProfile apply(ProfileDraft d, {DateTime? now}) {
    final DateTime stamp = now ?? DateTime.now();
    final DateTime? dob = d.dateOfBirth ?? dateOfBirth;
    final String? sex = d.sexAtBirth ?? sexAtBirth;
    final int? years = dob == null ? null : ageAt(dob, today: stamp);
    final ProfileConsent? nextConsent = d.grantConsent
        ? ProfileConsent(
            terms: true,
            healthData: true,
            version: kConsentVersion,
            acceptedAt: stamp,
          )
        : consent;
    final bool female = sex == 'female';
    final bool maleOver40 = sex == 'male' && (years ?? 0) >= 40;
    final String? nextName = d.name ?? name;
    return PatientProfile(
      id: id,
      name: nextName,
      email: email,
      dateOfBirth: dob,
      age: years ?? age,
      sexAtBirth: sex,
      consent: nextConsent,
      conditions: d.conditions ?? conditions,
      allergies: d.allergies ?? allergies,
      takesMedicines: d.takesMedicines ?? takesMedicines,
      medications: d.medications ?? medications,
      pregnancyStatus: female ? (d.pregnancyStatus ?? pregnancyStatus) : null,
      prostateUrinaryIssue: maleOver40
          ? (d.prostateUrinaryIssue ?? prostateUrinaryIssue)
          : null,
      firstGoal: d.firstGoal ?? firstGoal,
      heightCm: d.heightCm ?? heightCm,
      weightKg: d.weightKg ?? weightKg,
      onboardingComplete:
          (nextName?.trim().isNotEmpty ?? false) &&
          dob != null &&
          sex != null &&
          (nextConsent?.complete ?? false),
    );
  }

  /// Everything health-related cleared, as `DELETE /profile` does. Name and
  /// email stay.
  PatientProfile cleared() => PatientProfile(id: id, name: name, email: email);
}

/// Policy version stamped on a new consent (the server does this for real;
/// the fake mirrors it).
const String kConsentVersion = '2026-10';

/// A partial update for `PUT /profile`: every field optional, and only the
/// fields that are set are sent, so a screen can save just what it edits.
class ProfileDraft {
  const ProfileDraft({
    this.name,
    this.dateOfBirth,
    this.sexAtBirth,
    this.grantConsent = false,
    this.conditions,
    this.allergies,
    this.takesMedicines,
    this.medications,
    this.pregnancyStatus,
    this.prostateUrinaryIssue,
    this.firstGoal,
    this.heightCm,
    this.weightKg,
  });

  final String? name;
  final DateTime? dateOfBirth;
  final String? sexAtBirth;

  /// Sends `consent: {terms: true, health_data: true}`. Consent is never
  /// withdrawn through a draft (that is `DELETE /profile`).
  final bool grantConsent;

  /// Comma separated. An empty string clears the list; null leaves it.
  final String? conditions;
  final String? allergies;
  final bool? takesMedicines;
  final String? medications;
  final String? pregnancyStatus;
  final String? prostateUrinaryIssue;
  final String? firstGoal;
  final double? heightCm;
  final double? weightKg;

  bool get isEmpty => toJson().isEmpty;

  /// Fields from [other] win where both are set.
  ProfileDraft merge(ProfileDraft other) => ProfileDraft(
    name: other.name ?? name,
    dateOfBirth: other.dateOfBirth ?? dateOfBirth,
    sexAtBirth: other.sexAtBirth ?? sexAtBirth,
    grantConsent: grantConsent || other.grantConsent,
    conditions: other.conditions ?? conditions,
    allergies: other.allergies ?? allergies,
    takesMedicines: other.takesMedicines ?? takesMedicines,
    medications: other.medications ?? medications,
    pregnancyStatus: other.pregnancyStatus ?? pregnancyStatus,
    prostateUrinaryIssue: other.prostateUrinaryIssue ?? prostateUrinaryIssue,
    firstGoal: other.firstGoal ?? firstGoal,
    heightCm: other.heightCm ?? heightCm,
    weightKg: other.weightKg ?? weightKg,
  );

  /// Only the fields that were set.
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (name != null) 'name': name,
    if (dateOfBirth != null) 'date_of_birth': formatIsoDate(dateOfBirth!),
    if (sexAtBirth != null) 'sex_at_birth': sexAtBirth,
    if (grantConsent) 'consent': ProfileConsent.grantJson,
    if (conditions != null) 'conditions': conditions,
    if (allergies != null) 'allergies': allergies,
    if (takesMedicines != null) 'takes_medicines': takesMedicines,
    if (medications != null) 'medications': medications,
    if (pregnancyStatus != null) 'pregnancy_status': pregnancyStatus,
    if (prostateUrinaryIssue != null)
      'prostate_urinary_issue': prostateUrinaryIssue,
    if (firstGoal != null) 'first_goal': firstGoal,
    if (heightCm != null) 'height_cm': heightCm,
    if (weightKg != null) 'weight_kg': weightKg,
  };
}

abstract class ProfileRepository {
  Future<PatientProfile> fetch();

  /// Partial update: only the fields set on [draft] change.
  Future<PatientProfile> save(ProfileDraft draft);

  /// Clears health details and consent (name and email stay).
  Future<void> delete();
}

/// `2026-10-25` for a date (no time, no zone).
String formatIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime? _parseDateTime(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

String? _lower(String? raw) {
  final String? value = raw?.trim().toLowerCase();
  return value == null || value.isEmpty ? null : value;
}
