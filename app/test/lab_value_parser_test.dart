import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/features/reports/data/lab_value_parser.dart';
import 'package:tahasync_medaix/features/reports/data/report_models.dart';

void main() {
  group('parseLabValues', () {
    test('value above a printed range is High', () {
      final values = parseLabValues('HbA1c 6.4 % (4.0 - 6.0)');
      expect(values, hasLength(1));
      final v = values.single;
      expect(v.name, 'HbA1c');
      expect(v.value, '6.4 %');
      expect(v.status, ValueStatus.warn);
      expect(v.statusText, 'High');
      expect(v.explanation, contains('Average blood sugar'));
      expect(v.explanation, contains('Normal is 4 to 6.'));
    });

    test('value inside the range is Normal', () {
      final v = parseLabValues('Creatinine 0.9 mg/dL (0.6 - 1.2)').single;
      expect(v.name, 'Creatinine');
      expect(v.value, '0.9 mg/dL');
      expect(v.status, ValueStatus.ok);
      expect(v.statusText, 'Normal');
      expect(v.explanation, contains('kidneys'));
    });

    test('just past the limit is Slightly high / Slightly low', () {
      expect(
        parseLabValues('Glucose 104 mg/dL (70 - 100)').single.statusText,
        'Slightly high',
      );
      expect(
        parseLabValues('Hemoglobin 12.6 g/dL (13 - 17)').single.statusText,
        'Slightly low',
      );
    });

    test('far past the limit is Very high / Very low with error status', () {
      final high = parseLabValues('TSH 7.2 mIU/L (0.4 - 4.0)').single;
      expect(high.status, ValueStatus.error);
      expect(high.statusText, 'Very high');
      final low = parseLabValues('Ferritin 4 ng/mL (12 - 150)').single;
      expect(low.status, ValueStatus.error);
      expect(low.statusText, 'Very low');
    });

    test('"< limit" ranges', () {
      final ok = parseLabValues('LDL cholesterol 92 mg/dL (< 100)').single;
      expect(ok.status, ValueStatus.ok);
      expect(ok.explanation, contains('Normal is under 100.'));
      final high = parseLabValues('LDL cholesterol 130 mg/dL (< 100)').single;
      expect(high.statusText, 'High');
    });

    test('"> limit" ranges', () {
      final ok = parseLabValues('HDL 52 mg/dL (> 40)').single;
      expect(ok.status, ValueStatus.ok);
      expect(ok.explanation, contains('Normal is over 40.'));
      final low = parseLabValues('HDL 32 mg/dL (> 40)').single;
      expect(low.status, ValueStatus.warn);
      expect(low.statusText, 'Low');
    });

    test('a line without a unit or a range is skipped', () {
      expect(parseLabValues('Patient age 45'), isEmpty);
      expect(parseLabValues('Total 200'), isEmpty);
      expect(parseLabValues('Date 12/03/2026'), isEmpty);
    });

    test('a unit without a range gives a neutral "No range"', () {
      final v = parseLabValues('Platelets 250 x10^3/uL').single;
      expect(v.status, ValueStatus.neutral);
      expect(v.statusText, 'No range');
      expect(v.explanation, contains('No range was printed.'));
    });

    test('parses several lines in order, keeps names tidy', () {
      final values = parseLabValues(
        'Lab results\n'
        'HbA1c 6.4 % (4.0 - 6.0)\n'
        'Fasting glucose: 118 mg/dL (70 - 100)\n'
        '\n'
        'Creatinine 0.9 mg/dL 0.6 - 1.2\n'
        'Vitamin D 25 ng/mL (30 - 100)\n'
        'Reported by Dr. Ahmed\n',
      );
      expect(values.map((v) => v.name), <String>[
        'HbA1c',
        'Fasting glucose',
        'Creatinine',
        'Vitamin D',
      ]);
      expect(values[1].statusText, 'High');
      expect(values[3].statusText, 'Low');
    });

    test('explanations match whole words, not fragments', () {
      // "HBsAg" must not borrow the haemoglobin sentence via "hb".
      final v = parseLabValues('HBsAg 0.3 IU/mL (< 1.0)').single;
      expect(v.explanation, startsWith('Compare with the range'));
    });

    test('returns at most 12 values', () {
      final text = List<String>.generate(
        20,
        (i) => 'Marker$i ${i + 1} mg/dL (0 - 100)',
      ).join('\n');
      expect(parseLabValues(text), hasLength(12));
    });
  });

  group('guessReportTitle', () {
    test('lipids win', () {
      expect(guessReportTitle('Total cholesterol 168 mg/dL'), 'Lipid profile');
    });

    test('thyroid', () {
      expect(guessReportTitle('TSH 2.1 mIU/L'), 'Thyroid test');
    });

    test('liver needs whole words, not "total" or "fasting"', () {
      expect(guessReportTitle('ALT 30 U/L\nAST 28 U/L'), 'Liver function test');
      expect(
        guessReportTitle('Fasting glucose 118 mg/dL\nTotal protein 7 g/dL'),
        'Blood sugar test',
      );
    });

    test('sugar before blood count so glycated hemoglobin is a sugar test', () {
      expect(
        guessReportTitle('Glycated hemoglobin (HbA1c) 6.4 %'),
        'Blood sugar test',
      );
      expect(guessReportTitle('Hemoglobin 13.5 g/dL'), 'Blood test');
    });

    test('falls back to Lab report', () {
      expect(guessReportTitle('Nothing recognisable here'), 'Lab report');
    });
  });

  group('leadSentences', () {
    test('takes the first two sentences and preserves report list layout', () {
      expect(
        leadSentences('One is here.\nTwo   is here! Three is here.'),
        'One is here.\nTwo is here!',
      );
    });

    test('keeps structured lab summary rows on separate lines', () {
      const String summary =
          'Readable values from the scan:\n'
          '- Ferritin - 53.0 ng/mL\n'
          '\n'
          'Check each entry against the original; this is not a diagnosis.';
      expect(leadSentences(summary), summary);
    });

    test('returns everything when there are fewer sentences', () {
      expect(leadSentences('Only one.'), 'Only one.');
      expect(leadSentences('No terminator at all'), 'No terminator at all');
    });

    test('does not split on decimals', () {
      expect(
        leadSentences('Your HbA1c is 6.4 %. Fine otherwise. Extra.'),
        'Your HbA1c is 6.4 %. Fine otherwise.',
      );
    });

    test('empty in, empty out', () {
      expect(leadSentences('   '), '');
    });
  });
}
