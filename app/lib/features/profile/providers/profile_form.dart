/// Shared options, validation and unit maths for the questionnaire
/// (`docs/questionnaire.md`), used by sign-up, onboarding and Profile so all
/// three accept exactly the same values and send the same wire enums.
library;

import '../data/profile_repository.dart';

/// A wire value with its on-screen label.
typedef Option = ({String value, String label});

/// 1.5 — sex at birth.
const List<Option> kSexOptions = <Option>[
  (value: 'female', label: 'Female'),
  (value: 'male', label: 'Male'),
  (value: 'prefer_not_to_say', label: 'Prefer not to say'),
];

/// Helper copy under 1.5, from the spec.
const String kSexHelper =
    'Needed for correct lab ranges and to show the right questions on the '
    'next screen.';

/// The two "escape" chips that clear everything else when chosen.
const String kNoneOption = 'None';
const String kPreferNotToSayOption = 'Prefer not to say';
const Set<String> kExclusiveOptions = <String>{
  kNoneOption,
  kPreferNotToSayOption,
};

/// 2.1 — ongoing conditions.
const List<String> kConditionOptions = <String>[
  'Diabetes',
  'Hypertension',
  'Heart disease',
  'Asthma',
  'Thyroid',
  'Kidney disease',
  kNoneOption,
  kPreferNotToSayOption,
];

/// 2.2 — allergies.
const List<String> kAllergyOptions = <String>[
  'Penicillin',
  'Aspirin or NSAIDs',
  'Peanuts',
  'Dairy',
  'Seafood',
  kNoneOption,
  kPreferNotToSayOption,
];

/// 2.4F — pregnant or breastfeeding (female only).
const List<Option> kPregnancyOptions = <Option>[
  (value: 'no', label: 'No'),
  (value: 'pregnant', label: 'Pregnant'),
  (value: 'breastfeeding', label: 'Breastfeeding'),
  (value: 'prefer_not_to_say', label: 'Prefer not to say'),
];

/// 2.4M — prostate or urinary problems (male 40+ only).
const List<Option> kProstateOptions = <Option>[
  (value: 'no', label: 'No'),
  (value: 'yes', label: 'Yes'),
  (value: 'prefer_not_to_say', label: 'Prefer not to say'),
];

/// 3.1 — what to help with first.
const List<Option> kGoalOptions = <Option>[
  (value: 'reports', label: 'Understand my lab reports'),
  (value: 'medicines', label: 'Check my medicines'),
  (value: 'condition', label: 'Track a condition'),
  (value: 'habits', label: 'Build healthy habits'),
];

/// Placeholder policy links until the real pages are published.
const String kTermsUrl = 'https://medaix.app/terms';
const String kPrivacyUrl = 'https://medaix.app/privacy';

/// 1.6 and 1.7, word for word from the spec.
const String kTermsConsentText = 'I agree to the Terms and Privacy Policy';
const String kHealthConsentText =
    'I agree MedAIx may process my health data to explain my reports. I '
    'understand it gives information and is not a diagnosis';

/// 1.4 — shown when the date of birth makes the user under 18.
const String kUnderAgeMessage =
    'MedAIx is for adults. A parent or guardian can use it for you.';

/// Label for a wire value in [options]; falls back to a capitalised value.
String optionLabel(List<Option> options, String? value) {
  if (value == null || value.isEmpty) return 'Not set';
  for (final Option option in options) {
    if (option.value == value) return option.label;
  }
  return value[0].toUpperCase() + value.substring(1).replaceAll('_', ' ');
}

String sexLabel(String? value) => optionLabel(kSexOptions, value);

/// Toggles [label] in a multi-select where [kExclusiveOptions] stand alone:
/// picking "None" or "Prefer not to say" clears the rest, and picking
/// anything else clears them.
Set<String> toggleExclusive(Set<String> current, String label) {
  final Set<String> next = Set<String>.of(current);
  if (kExclusiveOptions.contains(label)) {
    if (next.contains(label)) {
      next.remove(label);
    } else {
      next
        ..clear()
        ..add(label);
    }
  } else {
    next.removeAll(kExclusiveOptions);
    if (!next.add(label)) next.remove(label);
  }
  return next;
}

/// Splits "Metformin 500 mg, Amlodipine" / one-per-line text into names.
List<String> splitNames(String raw) => raw
    .split(RegExp(r'[,;\n]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

abstract final class ProfileValidation {
  static const int minNameLength = 2;
  static const int maxNameLength = 60;
  static const int minAge = 18;
  static const int minYear = 1900;
  static const double minHeightCm = 50;
  static const double maxHeightCm = 250;
  static const double minWeightKg = 2;
  static const double maxWeightKg = 400;
  static const int minPasswordLength = 8;

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// 1.1 — 2 to 60 characters.
  static String? name(String? raw) {
    final String value = (raw ?? '').trim();
    if (value.isEmpty) return 'Enter your name.';
    if (value.length < minNameLength || value.length > maxNameLength) {
      return 'Use a name between 2 and 60 characters.';
    }
    return null;
  }

  static String? email(String? raw) {
    final String value = (raw ?? '').trim();
    if (value.isEmpty) return 'Enter your email address.';
    if (!_emailPattern.hasMatch(value)) {
      return 'That doesn’t look like an email address.';
    }
    return null;
  }

  static bool passwordLongEnough(String raw) => raw.length >= minPasswordLength;
  static bool passwordHasLetter(String raw) =>
      RegExp(r'[A-Za-z]').hasMatch(raw);
  static bool passwordHasNumber(String raw) => RegExp(r'[0-9]').hasMatch(raw);

  /// 1.3 — 8+ characters with a letter and a number.
  static String? password(String? raw) {
    final String value = raw ?? '';
    if (!passwordLongEnough(value) ||
        !passwordHasLetter(value) ||
        !passwordHasNumber(value)) {
      return 'Use 8 or more characters with a letter and a number.';
    }
    return null;
  }

  /// 1.4 — 18 or older, not in the future, not before 1900.
  static String? dateOfBirth(DateTime? value, {DateTime? today}) {
    if (value == null) return 'Choose your date of birth.';
    final DateTime now = today ?? DateTime.now();
    if (value.isAfter(now)) return 'That date is in the future.';
    if (value.year < minYear) return 'Choose a date after 1900.';
    if (PatientProfile.ageAt(value, today: now) < minAge) {
      return kUnderAgeMessage;
    }
    return null;
  }

  static String? sex(String? value) {
    if (value == null || value.isEmpty) {
      return 'Choose one option, or “Prefer not to say”.';
    }
    return null;
  }

  /// Optional: null (not answered) passes; NaN (mistyped) and out-of-range
  /// values fail.
  static String? heightCm(double? value) {
    if (value == null) return null;
    if (value.isNaN) return 'Enter your height as a number.';
    if (value < minHeightCm || value > maxHeightCm) {
      return 'Enter a height between 50 and 250 cm (1 ft 8 in to 8 ft 2 in).';
    }
    return null;
  }

  static String? weightKg(double? value) {
    if (value == null) return null;
    if (value.isNaN) return 'Enter your weight as a number.';
    if (value < minWeightKg || value > maxWeightKg) {
      return 'Enter a weight between 2 and 400 kg (4 and 880 lb).';
    }
    return null;
  }

  /// "172" rather than "172.0" for whole numbers.
  static String formatNumber(double? value, {int decimals = 1}) {
    if (value == null) return '';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(decimals);
  }
}

/// Height and weight units for the 3.2 toggle. Values are always stored in
/// centimetres and kilograms; this only changes what the user types.
enum UnitSystem { metric, imperial }

abstract final class Units {
  static const double cmPerInch = 2.54;
  static const double kgPerLb = 0.45359237;

  /// 170 cm → (5 ft, 7 in). Inches round to the nearest whole inch and
  /// carry into feet at 12.
  static ({int feet, int inches}) cmToFeetInches(double cm) {
    int totalInches = (cm / cmPerInch).round();
    if (totalInches < 0) totalInches = 0;
    return (feet: totalInches ~/ 12, inches: totalInches % 12);
  }

  /// 5 ft 7 in → 170 cm (whole centimetres).
  static double feetInchesToCm(int feet, int inches) =>
      ((feet * 12 + inches) * cmPerInch).roundToDouble();

  /// 68 kg → 150 lb (whole pounds).
  static int kgToLb(double kg) => (kg / kgPerLb).round();

  /// 150 lb → 68.0 kg (one decimal).
  static double lbToKg(double lb) =>
      double.parse((lb * kgPerLb).toStringAsFixed(1));

  static String heightLabel(double? cm, UnitSystem unit) {
    if (cm == null) return 'Not set';
    if (unit == UnitSystem.metric) {
      return '${ProfileValidation.formatNumber(cm)} cm';
    }
    final (:int feet, :int inches) = cmToFeetInches(cm);
    return '$feet ft $inches in';
  }

  static String weightLabel(double? kg, UnitSystem unit) {
    if (kg == null) return 'Not set';
    if (unit == UnitSystem.metric) {
      return '${ProfileValidation.formatNumber(kg)} kg';
    }
    return '${kgToLb(kg)} lb';
  }
}

/// Reads a typed number; empty → null, junk → NaN so validators can tell
/// "not answered" from "mistyped".
double? parseNumber(String raw) {
  final String value = raw.trim().replaceAll(',', '.');
  if (value.isEmpty) return null;
  return double.tryParse(value) ?? double.nan;
}

/// Formats a date of birth for display: 14 May 1990.
String formatLongDate(DateTime d) =>
    '${d.day} ${kMonthNames[d.month - 1]} ${d.year}';

const List<String> kMonthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
