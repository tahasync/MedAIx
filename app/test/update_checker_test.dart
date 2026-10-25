import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tahasync_medaix/core/update_checker.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';

import 'support/test_app.dart';

/// A `releases/latest` payload shaped like MedAIx's real releases: a sprint
/// tag that is not semver, and the workflow's versioned APK asset.
String releaseJson({
  String tag = 'sprint-2-wk-03-04',
  String? apkName = 'MedAIx-sprint-2-wk-03-04-v0.1.1-2-release.apk',
  String body = '### Added\n- Something new',
}) {
  return jsonEncode({
    'tag_name': tag,
    'html_url': 'https://github.com/tahasync/MedAIx/releases/tag/$tag',
    'body': body,
    'published_at': '2026-10-20T10:00:00Z',
    'assets': [
      // A non-APK asset first, to prove it is skipped.
      {
        'name': 'checksums.txt',
        'browser_download_url':
            'https://github.com/tahasync/MedAIx/releases/download/$tag/checksums.txt',
      },
      if (apkName != null)
        {
          'name': apkName,
          'browser_download_url':
              'https://github.com/tahasync/MedAIx/releases/download/$tag/$apkName',
        },
    ],
  });
}

void main() {
  group('parseReleaseVersion', () {
    test('reads version and build from the workflow APK asset name', () {
      expect(
        parseReleaseVersion('MedAIx-sprint-2-wk-03-04-v0.1.1-2-release.apk'),
        const ReleaseVersion(0, 1, 1, build: 2),
      );
    });

    test('APK match is case-insensitive and ignores the prefix', () {
      expect(
        parseReleaseVersion('medaix-main-V1.12.3-45-RELEASE.APK'),
        const ReleaseVersion(1, 12, 3, build: 45),
      );
    });

    test('a sprint tag carries no version', () {
      expect(parseReleaseVersion('sprint-2-wk-03-04'), isNull);
    });

    test('falls back to a v-prefixed or bare semver tag', () {
      expect(parseReleaseVersion('v0.1.1'), const ReleaseVersion(0, 1, 1));
      expect(parseReleaseVersion('0.1.1'), const ReleaseVersion(0, 1, 1));
      expect(
        parseReleaseVersion('v0.1.1+2'),
        const ReleaseVersion(0, 1, 1, build: 2),
      );
      expect(
        parseReleaseVersion('v0.1.1-2'),
        const ReleaseVersion(0, 1, 1, build: 2),
      );
    });

    test('rejects anything else', () {
      expect(parseReleaseVersion(''), isNull);
      expect(parseReleaseVersion('latest'), isNull);
      expect(parseReleaseVersion('v1.2'), isNull);
      expect(parseReleaseVersion('MedAIx-v0.1.1-release.apk'), isNull);
    });
  });

  group('isNewerVersion', () {
    const installed = ReleaseVersion(0, 1, 1, build: 2);

    test('same version and build is not newer', () {
      expect(isNewerVersion(installed, installed), isFalse);
    });

    test('same version with a higher build is newer', () {
      expect(
        isNewerVersion(installed, const ReleaseVersion(0, 1, 1, build: 3)),
        isTrue,
      );
    });

    test('same version with a lower build is not newer', () {
      expect(
        isNewerVersion(installed, const ReleaseVersion(0, 1, 1, build: 1)),
        isFalse,
      );
    });

    test('a higher version wins even with a lower build', () {
      expect(
        isNewerVersion(installed, const ReleaseVersion(0, 1, 2, build: 1)),
        isTrue,
      );
      expect(isNewerVersion(installed, const ReleaseVersion(0, 2, 0)), isTrue);
      expect(isNewerVersion(installed, const ReleaseVersion(1, 0, 0)), isTrue);
    });

    test('a lower version loses even with a higher build', () {
      expect(
        isNewerVersion(installed, const ReleaseVersion(0, 1, 0, build: 99)),
        isFalse,
      );
    });

    test('label renders pubspec style', () {
      expect(installed.label, 'v0.1.1+2');
      expect(const ReleaseVersion(0, 1, 1).label, 'v0.1.1');
    });
  });

  group('UpdateInfo.fromJson', () {
    test('takes the version and download URL from the APK asset', () {
      final info = UpdateInfo.fromJson(
        jsonDecode(releaseJson()) as Map<String, dynamic>,
      )!;
      expect(info.tagName, 'sprint-2-wk-03-04');
      expect(info.version, const ReleaseVersion(0, 1, 1, build: 2));
      expect(info.versionLabel, 'v0.1.1+2');
      expect(info.apkUrl, endsWith('-v0.1.1-2-release.apk'));
      expect(info.downloadUrl, info.apkUrl);
    });

    test('falls back to a semver tag and the release page', () {
      final info = UpdateInfo.fromJson(
        jsonDecode(releaseJson(tag: 'v0.2.0', apkName: null))
            as Map<String, dynamic>,
      )!;
      expect(info.version, const ReleaseVersion(0, 2, 0));
      expect(info.apkUrl, isNull);
      expect(info.downloadUrl, info.htmlUrl);
    });

    test('a sprint tag with no APK has no version', () {
      final info = UpdateInfo.fromJson(
        jsonDecode(releaseJson(apkName: null)) as Map<String, dynamic>,
      )!;
      expect(info.version, isNull);
      expect(info.versionLabel, 'sprint-2-wk-03-04');
    });

    test('an APK without a version slug still provides the download URL', () {
      final info = UpdateInfo.fromJson(
        jsonDecode(releaseJson(apkName: 'MedAIx.apk')) as Map<String, dynamic>,
      )!;
      expect(info.version, isNull);
      expect(info.apkUrl, endsWith('/MedAIx.apk'));
    });

    test('no tag means no release', () {
      expect(UpdateInfo.fromJson(<String, dynamic>{'html_url': 'x'}), isNull);
    });
  });

  group('UpdateChecker.checkForUpdate', () {
    const installed = ReleaseVersion(0, 1, 1, build: 2);

    UpdateChecker checker(MockClient mock, {bool force = false}) =>
        UpdateChecker(client: mock, forceUpdate: force);

    test('offers a release whose APK is a newer build', () async {
      http.Request? seen;
      final result = await checker(
        MockClient((request) async {
          seen = request;
          return http.Response(
            releaseJson(
              apkName: 'MedAIx-sprint-3-wk-05-06-v0.1.1-3-release.apk',
            ),
            200,
          );
        }),
      ).checkForUpdate(installed: installed);

      expect(result, isNotNull);
      expect(result!.version, const ReleaseVersion(0, 1, 1, build: 3));
      expect(seen!.url.toString(), AppUpdateConfig.apiUrl);
      expect(seen!.headers['Accept'], contains('github'));
    });

    test('is quiet when the release matches the installed build', () async {
      final result = await checker(
        MockClient((_) async => http.Response(releaseJson(), 200)),
      ).checkForUpdate(installed: installed);
      expect(result, isNull);
    });

    test('is quiet when the release is older', () async {
      final result = await checker(
        MockClient(
          (_) async => http.Response(
            releaseJson(apkName: 'MedAIx-x-v0.1.0-9-release.apk'),
            200,
          ),
        ),
      ).checkForUpdate(installed: installed);
      expect(result, isNull);
    });

    test('is quiet when the release has no parseable version', () async {
      final result = await checker(
        MockClient((_) async => http.Response(releaseJson(apkName: null), 200)),
      ).checkForUpdate(installed: installed);
      expect(result, isNull);
    });

    test('swallows non-200, malformed JSON, and transport errors', () async {
      for (final mock in <MockClient>[
        MockClient((_) async => http.Response('rate limited', 403)),
        MockClient((_) async => http.Response('not json', 200)),
        MockClient((_) async => http.Response('[]', 200)),
        MockClient((_) async => throw http.ClientException('offline')),
      ]) {
        expect(
          await checker(mock).checkForUpdate(installed: installed),
          isNull,
        );
      }
    });

    test('skips the network when the installed version is unknown', () async {
      var calls = 0;
      final result = await checker(
        MockClient((_) async {
          calls++;
          return http.Response(releaseJson(), 200);
        }),
      ).checkForUpdate(installed: null);
      expect(result, isNull);
      expect(calls, 0);
    });

    test('force flag offers whatever release is fetched', () async {
      final mock = MockClient((_) async => http.Response(releaseJson(), 200));
      expect(
        await checker(mock, force: true).checkForUpdate(installed: installed),
        isNotNull,
      );
      expect(
        await checker(mock, force: true).checkForUpdate(installed: null),
        isNotNull,
      );
    });

    test('force flag defaults to off', () {
      expect(AppUpdateConfig.forceUpdate, isFalse);
      expect(
        UpdateChecker(
          client: MockClient((_) async {
            return http.Response('', 500);
          }),
        ).forceUpdate,
        isFalse,
      );
    });
  });

  group('formatChangelog — markup never reaches the dialog', () {
    test('strips heading hashes', () {
      final out = formatChangelog('### Fixed\n- Something broke');
      expect(out, isNot(contains('#')));
      expect(out, contains('FIXED'));
    });

    test('replaces list markers with a bullet', () {
      final out = formatChangelog('### Fixed\n- Urdu OCR dropped digits');
      expect(out, isNot(contains('- Urdu')));
      expect(out, contains('• Urdu OCR dropped digits'));
    });

    test('strips bold and inline-code delimiters', () {
      final out = formatChangelog(
        '- Read `confidence` and **flag** low values. See *the* note.',
      );
      expect(out, isNot(contains('`')));
      expect(out, isNot(contains('**')));
      expect(out, isNot(contains('*the*')));
      expect(out, contains('Read confidence and flag low values.'));
    });

    test('strips markdown links down to their label', () {
      final out = formatChangelog('- See [the notes](https://example.com/x).');
      expect(out, isNot(contains('https://')));
      expect(out, isNot(contains('](')));
      expect(out, contains('See the notes.'));
    });

    test('drops the Full Changelog trailer and bare URLs', () {
      final out = formatChangelog(
        '- Fixed a bug.\n\n'
        '**Full Changelog**: https://github.com/a/b/compare/v1..v2',
      );
      expect(out, isNot(contains('Full Changelog')));
      expect(out, isNot(contains('github.com')));
    });
  });

  group('formatChangelog — hard-wrapped source is unwrapped', () {
    test('re-joins a bullet broken across lines', () {
      const wrapped =
          '- **Reference ranges were rewritten.** When a lab printed\n'
          '  a range with a unit, the simplifier changed the number as\n'
          '  well as the words.';
      final out = formatChangelog(wrapped);
      expect(
        out,
        contains(
          'a range with a unit, the simplifier changed the number as '
          'well as the words.',
        ),
      );
    });

    test('re-joins a paragraph broken across lines', () {
      const wrapped =
          'Two OCR fixes for Urdu reports,\n'
          'plus the CI gate that keeps source formatting from drifting.';
      final out = formatChangelog(wrapped);
      expect(
        out,
        'Two OCR fixes for Urdu reports, plus the CI gate that keeps source '
        'formatting from drifting.',
      );
    });

    test('normalizes CRLF input', () {
      final out = formatChangelog('### Fixed\r\n- A bug\r\n  was fixed.');
      expect(out, contains('FIXED'));
      expect(out, contains('• A bug was fixed.'));
      expect(out, isNot(contains('\r')));
    });

    test('keeps real paragraph breaks', () {
      final out = formatChangelog(
        'First para line one.\nFirst para line two.\n\nSecond para.',
      );
      expect(out, 'First para line one. First para line two.\n\nSecond para.');
    });
  });

  group('formatChangelog — structure', () {
    test('a heading separates blocks with a blank line', () {
      final out = formatChangelog('### Fixed\n- One\n\n### Added\n- Two');
      expect(out, 'FIXED\n\n• One\n\nADDED\n\n• Two');
    });

    test('a paragraph after a blank line is not absorbed into the bullet', () {
      final out = formatChangelog('- A bullet\n\nA separate paragraph.');
      expect(out, '• A bullet\n\nA separate paragraph.');
    });

    test('empty and whitespace-only input gets a real message', () {
      const fallback = 'No changelog available for this release.';
      expect(formatChangelog(''), fallback);
      expect(formatChangelog('   \n\n  '), fallback);
    });

    test('input that is only markup and URLs gets the fallback', () {
      expect(
        formatChangelog(
          '**Full Changelog**: https://github.com/a/b/compare/1..2',
        ),
        'No changelog available for this release.',
      );
    });
  });

  group('formatChangelog — a realistic release body', () {
    const body = '''
Sign-in, onboarding and the simplified-report history, plus two OCR fixes
for Urdu reports.

### Added
- **Google sign-in and email/password accounts.** Reports are now stored
  against the signed-in patient, so a reinstall keeps the history. The
  `/reports` list refreshes itself after every upload.
- **Simplified reports.** Medical terms are reworded in plain language;
  values and reference ranges stay *exactly* as printed.

### Fixed
- Urdu OCR dropped digits next to `mg/dL` when the scan was skewed by more
  than 3 degrees. See [the issue](https://github.com/tahasync/MedAIx/issues/12).

**Full Changelog**: https://github.com/tahasync/MedAIx/compare/a...b
''';

    test('contains no markdown delimiters anywhere', () {
      final out = formatChangelog(body);
      for (final forbidden in ['#', '**', '`', '](', 'http']) {
        expect(
          out,
          isNot(contains(forbidden)),
          reason: 'leaked "$forbidden" into the dialog body',
        );
      }
    });

    test('preserves both sections and all three bullets', () {
      final out = formatChangelog(body);
      expect(out, contains('ADDED'));
      expect(out, contains('FIXED'));
      expect(out, contains('• Google sign-in and email/password accounts.'));
      expect(out, contains('• Simplified reports.'));
      expect(out, contains('• Urdu OCR dropped digits next to mg/dL'));
    });

    test('each bullet renders as exactly one unwrapped line', () {
      final out = formatChangelog(body);
      final bullets = out.split('\n').where((l) => l.startsWith('• ')).toList();
      expect(bullets, hasLength(3));
      for (final bullet in bullets) {
        expect(bullet, isNot(contains('  ')));
        expect(bullet, isNot(endsWith(',')));
      }
      expect(out, contains('skewed by more than 3 degrees. See the issue.'));
    });
  });

  group('update dialog once the shell is on screen', () {
    /// The real app on fakes, with the release check wired to a fake GitHub.
    Widget app({
      required ReleaseVersion installed,
      required String apkName,
      void Function()? onFetch,
    }) {
      return testApp(
        overrides: [
          installedVersionProvider.overrideWith((ref) async => installed),
          updateCheckerProvider.overrideWithValue(
            UpdateChecker(
              forceUpdate: false,
              client: MockClient((_) async {
                onFetch?.call();
                return http.Response(
                  releaseJson(
                    tag: 'sprint-3-wk-05-06',
                    apkName: apkName,
                    body: '### Added\n- Update prompt\n- Urdu **OCR** fixes',
                  ),
                  200,
                );
              }),
            ),
          ),
          // Re-enable the check that the harness silences by default.
          latestReleaseProvider.overrideWith((ref) async {
            final installed = await ref.watch(installedVersionProvider.future);
            return ref
                .read(updateCheckerProvider)
                .checkForUpdate(installed: installed);
          }),
        ],
      );
    }

    testWidgets('a newer release shows the dialog once, with both versions', (
      tester,
    ) async {
      await usePhone(tester);
      var fetches = 0;
      await tester.pumpWidget(
        app(
          installed: const ReleaseVersion(0, 1, 1, build: 2),
          apkName: 'MedAIx-sprint-3-wk-05-06-v0.1.2-3-release.apk',
          onFetch: () => fetches++,
        ),
      );
      await tester.pumpAndSettle();

      expect(fetches, 1);
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('v0.1.1+2'), findsOneWidget);
      expect(find.text('v0.1.2+3'), findsOneWidget);
      expect(find.text("What's new"), findsOneWidget);
      expect(find.textContaining('• Update prompt'), findsOneWidget);
      expect(find.textContaining('• Urdu OCR fixes'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Remind me later'), findsOneWidget);
      // Flat dialog: no blur, no gradient, no shadow.
      expect(find.byType(BackdropFilter), findsNothing);

      await tester.tap(find.text('Remind me later'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);

      // Switching tabs rebuilds the shell; it must not prompt again.
      await tester.tap(find.text('Meds'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('an equal or older release shows nothing', (tester) async {
      await usePhone(tester);
      for (final apk in <String>[
        'MedAIx-sprint-3-wk-05-06-v0.1.1-2-release.apk',
        'MedAIx-sprint-3-wk-05-06-v0.1.0-7-release.apk',
      ]) {
        await tester.pumpWidget(
          app(installed: const ReleaseVersion(0, 1, 1, build: 2), apkName: apk),
        );
        await tester.pumpAndSettle();

        expect(find.text('Update available'), findsNothing);
        expect(find.text('Update now'), findsNothing);
        expect(find.byType(FloatingNav), findsOneWidget);
      }
    });

    testWidgets('renders readably under the dark theme', (tester) async {
      await usePhone(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        app(
          installed: const ReleaseVersion(0, 1, 1, build: 2),
          apkName: 'MedAIx-sprint-3-wk-05-06-v0.1.2-3-release.apk',
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.text('Update available'));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(find.text('Update now'), findsOneWidget);
    });
  });
}
