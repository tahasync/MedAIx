import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user-facing source strings follow the copy guide', () {
    final banned = <String>[
      'Click here',
      'Submit',
      'Learn more',
      'Hurry',
      'Limited time',
      "Don't miss",
      'Yes, I want this',
      'coming soon',
    ];
    final stringLiteral = RegExp(r"""(['"])(.*?)(?<!\\)\1""");
    final violations = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in stringLiteral.allMatches(source)) {
        // Raw strings in this codebase are parsing patterns, not UI copy.
        if (match.start > 0 && source[match.start - 1].toLowerCase() == 'r') {
          continue;
        }
        final value = match
            .group(2)!
            .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
            .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), '');
        for (final phrase in banned) {
          if (value.toLowerCase().contains(phrase.toLowerCase())) {
            violations.add('${entity.path}: "$phrase"');
          }
        }
        if (value.contains('!')) violations.add('${entity.path}: "!"');
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
