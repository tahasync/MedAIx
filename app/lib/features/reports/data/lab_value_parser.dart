/// Turns OCR text into [ReportValue]s so a real report can render the same
/// per-value cards as the mockup.
///
/// Deliberately conservative: a line only counts when it has a name, a
/// number, and either a unit or a printed reference range. Numbers are
/// never changed; the status comes purely from comparing the value with the
/// range printed on the report.
library;

import 'report_models.dart';

final RegExp _linePattern = RegExp(
  r'^\s*(?<name>[A-Za-z][A-Za-z0-9 ()/%.\-]{1,40}?)\s*[:\-]?\s+'
  r'(?<value>\d+(?:\.\d+)?)\s*'
  r'(?<unit>%|mg/d[lL]|g/d[lL]|mmol/[lL]|[mµu]?IU/m?[lL]|U/[lL]|fL|pg|'
  r'ng/m[lL]|pg/m[lL]|mm/hr|x?10\^?\d+/?[a-zA-Zµ]*|/cumm|/[uµ][lL]|'
  r'million/cumm|cells/cumm|mEq/[lL]|µmol/[lL]|umol/[lL])?\s*'
  r'(?<range>\(?\s*(?<low>\d+(?:\.\d+)?)\s*(?:-|–|to)\s*(?<high>\d+(?:\.\d+)?)\s*\)?'
  r'|\(?\s*<\s*(?<lt>\d+(?:\.\d+)?)\s*\)?|\(?\s*>\s*(?<gt>\d+(?:\.\d+)?)\s*\)?)?',
);

/// Plain-language one-liners for common markers. Anything else gets a
/// neutral sentence so we never invent medicine.
const Map<String, String> _explanations = <String, String>{
  'hba1c': 'Average blood sugar over 3 months.',
  'glucose': 'Sugar in your blood. Fasting normal is under 100.',
  'fasting glucose': 'Sugar after fasting. Normal is under 100.',
  'creatinine': 'Shows how well your kidneys filter.',
  'urea': 'A waste product your kidneys clear.',
  'ldl': 'The “bad” cholesterol. Lower is better.',
  'ldl cholesterol': 'The “bad” cholesterol. Lower is better.',
  'hdl': 'The “good” cholesterol. Higher is better.',
  'hdl cholesterol': 'The “good” cholesterol. Higher is better.',
  'cholesterol': 'All cholesterol added together. Under 200 is good.',
  'total cholesterol': 'All cholesterol added together. Under 200 is good.',
  'triglycerides': 'Fat in your blood. Rises with sugar and fried food.',
  'hemoglobin': 'Carries oxygen. Low can mean anaemia.',
  'haemoglobin': 'Carries oxygen. Low can mean anaemia.',
  'hb': 'Carries oxygen. Low can mean anaemia.',
  'wbc': 'White cells fight infection.',
  'tlc': 'White cells fight infection.',
  'platelets': 'Help your blood clot.',
  'platelet count': 'Help your blood clot.',
  'tsh': 'Thyroid signal. High usually means an underactive thyroid.',
  'alt': 'A liver enzyme. High can mean liver strain.',
  'sgpt': 'A liver enzyme. High can mean liver strain.',
  'ast': 'A liver enzyme. High can mean liver or muscle strain.',
  'sgot': 'A liver enzyme. High can mean liver or muscle strain.',
  'vitamin d': 'Needed for bones. Low is common and treatable.',
  'ferritin': 'Stored iron. Low means iron stores are running out.',
  'esr': 'Rises with inflammation anywhere in the body.',
  'uric acid': 'High can cause gout.',
};

const int _maxValues = 12;

/// Parses [text] line by line. Returns at most 12 values, in order.
List<ReportValue> parseLabValues(String text) {
  final List<ReportValue> out = <ReportValue>[];
  for (final String rawLine in text.split(RegExp(r'\r?\n'))) {
    final String line = rawLine.trim();
    if (line.isEmpty) continue;
    final RegExpMatch? m = _linePattern.firstMatch(line);
    if (m == null) continue;
    final String? unit = m.namedGroup('unit');
    final String? range = m.namedGroup('range');
    if (unit == null && range == null) continue;

    final String name = _cleanName(m.namedGroup('name')!);
    if (name.length < 2) continue;
    final double value = double.parse(m.namedGroup('value')!);

    final double? low = _num(m.namedGroup('low'));
    final double? high = _num(m.namedGroup('high')) ?? _num(m.namedGroup('lt'));
    final double? gt = _num(m.namedGroup('gt'));

    final (ValueStatus status, String statusText) = _judge(
      value,
      low: low,
      high: high,
      greaterThan: gt,
    );

    out.add(
      ReportValue(
        name: name,
        value: unit == null ? _fmt(value) : '${_fmt(value)} $unit',
        status: status,
        statusText: statusText,
        explanation: _explain(name, status, low: low, high: high, gt: gt),
      ),
    );
    if (out.length >= _maxValues) break;
  }
  return out;
}

double? _num(String? s) => s == null ? null : double.tryParse(s);

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

String _cleanName(String raw) {
  String n = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  n = n.replaceAll(RegExp(r'[:\-]+$'), '').trim();
  if (n.isEmpty) return n;
  // Keep acronyms, sentence-case the rest.
  final bool acronym = n.length <= 5 && n.toUpperCase() == n;
  if (acronym) return n;
  return n[0].toUpperCase() + n.substring(1);
}

/// "Slightly" covers the first 5 % past a limit (6.4 against 6.0 is already
/// "High", as on the mockup); 50 % past it is "Very".
const double _slightly = 0.05;
const double _far = 0.5;

(ValueStatus, String) _judge(
  double value, {
  double? low,
  double? high,
  double? greaterThan,
}) {
  if (greaterThan != null) {
    if (value >= greaterThan) return (ValueStatus.ok, 'Normal');
    return _below(value, greaterThan);
  }
  if (high != null && value > high) return _above(value, high);
  if (low != null && value < low) return _below(value, low);
  if (low == null && high == null) return (ValueStatus.neutral, 'No range');
  return (ValueStatus.ok, 'Normal');
}

(ValueStatus, String) _above(double value, double high) {
  if (value > high * (1 + _far)) return (ValueStatus.error, 'Very high');
  if (value <= high * (1 + _slightly)) {
    return (ValueStatus.warn, 'Slightly high');
  }
  return (ValueStatus.warn, 'High');
}

(ValueStatus, String) _below(double value, double low) {
  if (value < low * (1 - _far)) return (ValueStatus.error, 'Very low');
  if (value >= low * (1 - _slightly)) return (ValueStatus.warn, 'Slightly low');
  return (ValueStatus.warn, 'Low');
}

/// Looks a marker up by its whole name, then by any whole word in it, so
/// "HBsAg" never borrows the haemoglobin sentence via a stray "hb".
String? _lookupExplanation(String key) {
  final String? direct = _explanations[key];
  if (direct != null) return direct;
  final List<String> words = key.split(' ');
  for (final MapEntry<String, String> e in _explanations.entries) {
    final List<String> parts = e.key.split(' ');
    for (int i = 0; i + parts.length <= words.length; i++) {
      bool same = true;
      for (int j = 0; j < parts.length; j++) {
        if (words[i + j] != parts[j]) {
          same = false;
          break;
        }
      }
      if (same) return e.value;
    }
  }
  return null;
}

String _explain(
  String name,
  ValueStatus status, {
  double? low,
  double? high,
  double? gt,
}) {
  final String key = name
      .toLowerCase()
      .replaceAll(RegExp(r'\s*\(.*\)'), '')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final String base =
      _lookupExplanation(key) ??
      'Compare with the range printed on your report.';
  if (status == ValueStatus.neutral) return '$base No range was printed.';
  if (low != null && high != null) {
    return '$base Normal is ${_fmt(low)} to ${_fmt(high)}.';
  }
  if (high != null) return '$base Normal is under ${_fmt(high)}.';
  if (gt != null) return '$base Normal is over ${_fmt(gt)}.';
  return base;
}

/// A short title for a report, guessed from the markers it contains.
///
/// Short marker names are matched as whole words: "alt" must not fire on
/// "total" or "health", and "ast" must not fire on "fasting".
String guessReportTitle(String text) {
  final String t = text.toLowerCase();
  bool word(String w) => RegExp('\\b$w\\b').hasMatch(t);

  if (t.contains('cholesterol') || t.contains('triglycerid')) {
    return 'Lipid profile';
  }
  if (word('tsh') || t.contains('thyroid')) return 'Thyroid test';
  if (t.contains('urine')) return 'Urine test';
  if (word('sgpt') || word('sgot') || (word('alt') && word('ast'))) {
    return 'Liver function test';
  }
  if (t.contains('glucose') || word('hba1c')) return 'Blood sugar test';
  if (t.contains('hemoglobin') ||
      t.contains('haemoglobin') ||
      t.contains('platelet')) {
    return 'Blood test';
  }
  return 'Lab report';
}

/// First one or two sentences of a plain-language text, for the summary
/// card. The full text stays available below it.
String leadSentences(String text, {int count = 2}) {
  final String flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return flat;
  final Iterable<RegExpMatch> ends = RegExp(r'[.!?](\s|$)').allMatches(flat);
  int taken = 0;
  for (final RegExpMatch m in ends) {
    taken++;
    if (taken == count) return flat.substring(0, m.end).trim();
  }
  return flat;
}
