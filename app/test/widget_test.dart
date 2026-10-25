import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/src/upload_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tahasync_medaix/main.dart';
import 'package:tahasync_medaix/src/api_client.dart';
import 'package:tahasync_medaix/src/auth.dart';
import 'package:tahasync_medaix/src/profile_screen.dart';
import 'package:tahasync_medaix/src/providers.dart';
import 'package:tahasync_medaix/src/router.dart';
import 'package:tahasync_medaix/src/simplify_screen.dart';
import 'package:tahasync_medaix/src/theme.dart';

/// Signed-in stand-in so home-screen tests do not call Supabase.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({this.session, this.configured = true});

  final AuthSession? session;
  final bool configured;

  @override
  bool get isConfigured => configured;

  @override
  AuthSession? get currentSession => session;

  @override
  Stream<AuthSession?> get authStateChanges => const Stream.empty();

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async => const AuthResult();

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
  }) async => const AuthResult();

  @override
  Future<AuthResult> signInWithGoogle() async => const AuthResult();

  @override
  Future<void> signOut() async {}
}

const _signedInSession = AuthSession(userId: 'user-1', accessToken: 'token');

const _completeProfile = PatientProfile(
  id: 1,
  name: 'Test',
  age: 30,
  weight: 70,
  height: 170,
  sex: 'female',
  conditions: '',
  medications: '',
  allergies: '',
  onboardingComplete: true,
);

Widget signedInApp({List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(session: _signedInSession),
      ),
      profileProvider.overrideWith((ref) async => _completeProfile),
      ...overrides,
    ],
    child: const MedAIxApp(),
  );
}

void main() {
  testWidgets('app boots and shows the MedAIx placeholder', (tester) async {
    await tester.pumpWidget(signedInApp());
    await tester.pumpAndSettle();

    expect(find.text('MedAIx'), findsWidgets);
    expect(find.text('Your report, in plain language.'), findsOneWidget);
    expect(find.text('Scan a report'), findsOneWidget);
    expect(find.text('Simplified reports'), findsOneWidget);
    expect(find.text('Your profile'), findsOneWidget);
    expect(find.textContaining(String.fromCharCode(0x00C2)), findsNothing);
  });

  test('both themes expose the semantic extension', () {
    for (final ThemeData theme in <ThemeData>[AppTheme.light, AppTheme.dark]) {
      expect(theme.extension<AppSemanticColors>(), isNotNull);
    }
  });

  test('light scheme uses the locked Steel primary', () {
    expect(AppTheme.light.colorScheme.primary, const Color(0xFF3D5387));
    expect(AppTheme.light.colorScheme.brightness, Brightness.light);
  });

  test('dark scheme uses the locked Ink background', () {
    expect(AppTheme.dark.colorScheme.primary, const Color(0xFF7C83AD));
    expect(AppTheme.dark.scaffoldBackgroundColor, const Color(0xFF0E0D15));
    expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
  });

  test('neither theme uses pure black or pure white backgrounds', () {
    // §3b guardrail.
    expect(
      AppTheme.light.scaffoldBackgroundColor,
      isNot(const Color(0xFFFFFFFF)),
    );
    expect(
      AppTheme.dark.scaffoldBackgroundColor,
      isNot(const Color(0xFF000000)),
    );
  });

  testWidgets('app renders under a forced dark theme', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(signedInApp());
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(
      find.text('Your report, in plain language.'),
    );
    expect(Theme.of(context).colorScheme.brightness, Brightness.dark);
  });

  testWidgets('upload screen offers English, Urdu, and Roman Urdu', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: UploadReportScreen(onPickFile: () async => null),
        ),
      ),
    );

    expect(find.text('Report language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<ReportOcrLanguage>));
    await tester.pumpAndSettle();
    expect(find.text('Urdu'), findsOneWidget);
    expect(find.text('Roman Urdu'), findsOneWidget);

    await tester.tap(find.text('Urdu').last);
    await tester.pumpAndSettle();
    expect(find.text('Urdu script + English lab labels'), findsOneWidget);
  });

  testWidgets('camera permission denial offers file selection fallback', (
    tester,
  ) async {
    var filePickerOpened = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: UploadReportScreen(
            onPickFile: () async {
              filePickerOpened = true;
              return null;
            },
            onTakePhoto: () async => null,
            onRequestCameraPermission: () async => false,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(find.text('Camera access'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Camera access not granted'), findsOneWidget);
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();

    expect(filePickerOpened, isTrue);
  });

  group('ApiClient.checkHealth', () {
    ApiClient clientWith(MockClient mock) =>
        ApiClient(baseUrl: 'http://localhost:8000', client: mock);

    test('returns true for a healthy service', () async {
      final client = clientWith(
        MockClient((_) async => http.Response('{"status":"ok"}', 200)),
      );

      expect(await client.checkHealth(), isTrue);
    });

    test('throws ApiException on a non-200 response', () async {
      final client = clientWith(
        MockClient((_) async => http.Response('{"status":"degraded"}', 503)),
      );

      expect(client.checkHealth(), throwsA(isA<ApiException>()));
    });

    // Regression: the http package reports a refused connection as
    // ClientException, which is not a SocketException. Missing this left the
    // UI's Loading state spinning forever on a dead backend.
    test(
      'wraps a refused connection (ClientException) in ApiException',
      () async {
        final client = clientWith(
          MockClient((_) async {
            throw http.ClientException('Connection closed before full header');
          }),
        );

        expect(
          client.checkHealth(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.error,
              'error',
              isA<http.ClientException>(),
            ),
          ),
        );
      },
    );

    // Driven by a fake clock rather than a real delay: the production timeout is
    // a build-time --dart-define, and each attempt is retried, so a wall-clock
    // sleep would be both flaky and slow. Elapsing past one attempt's deadline
    // is enough to trip it; the fake clock makes the remaining two free.
    test('wraps an expired deadline (TimeoutException) in ApiException', () {
      final client = clientWith(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(minutes: 5));
          return http.Response('{"status":"ok"}', 200);
        }),
      );

      Object? caught;
      fakeAsync((async) {
        // Block-bodied onError: an expression body would return the
        // assignment's value, which is not the Future<bool>'s type.
        client.checkHealth().then(
          (_) {},
          onError: (Object e) {
            caught = e;
          },
        );
        // 30s timeout + 2s retry gap, three times over, with slack.
        async.elapse(const Duration(minutes: 5));
      });

      expect(caught, isA<ApiException>());
    });

    // Cold starts, not breakage: Render's edge answers 502/503 while a
    // sleeping free instance boots. Retrying transparently is the difference
    // between "it worked on the second try" and a false alarm.
    test(
      'recovers when an early attempt fails but the service wakes',
      () async {
        var calls = 0;
        final client = clientWith(
          MockClient((_) async {
            calls++;
            if (calls == 1) throw http.ClientException('Connection reset');
            return http.Response('{"status":"ok"}', 200);
          }),
        );

        expect(await client.checkHealth(), isTrue);
        expect(calls, 2);
      },
    );

    // A 4xx is a real answer, not a blip. Retrying it only delays the error.
    test('does not retry a 4xx response', () async {
      var calls = 0;
      final client = clientWith(
        MockClient((_) async {
          calls++;
          return http.Response('nope', 404);
        }),
      );

      await expectLater(client.checkHealth(), throwsA(isA<ApiException>()));
      expect(calls, 1);
    });

    // Every attempt failing must still surface, not loop forever.
    test('gives up after the configured number of attempts', () async {
      var calls = 0;
      final client = clientWith(
        MockClient((_) async {
          calls++;
          throw http.ClientException('Connection refused');
        }),
      );

      await expectLater(client.checkHealth(), throwsA(isA<ApiException>()));
      expect(calls, 3);
    });

    // ApiException raised for a non-200 must not be re-wrapped, or callers
    // lose the status code they branch on.
    test('does not re-wrap ApiException', () async {
      final client = clientWith(
        MockClient((_) async => http.Response('nope', 500)),
      );

      await expectLater(
        client.checkHealth(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });
  });

  group('ApiClient.uploadReport', () {
    ApiClient clientWith(MockClient mock) =>
        ApiClient(baseUrl: 'http://localhost:8000', client: mock);

    late Directory tempDir;
    late String filePath;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('medaix_upload_test');
      filePath = '${tempDir.path}/report.pdf';
      // A minimal, non-empty payload so the multipart body is well-formed.
      File(
        filePath,
      ).writeAsBytesSync(const <int>[0x25, 0x50, 0x44, 0x46, 0x0A]); // '%PDF\n'
    });

    tearDownAll(() {
      tempDir.deleteSync(recursive: true);
    });

    test('returns the parsed OCR result on success', () async {
      final client = clientWith(
        MockClient(
          (_) async => http.Response(
            '{"id":7,"text":"Hemoglobin 13.2","confidence":91.5,'
            '"skew_corrected_degrees":0.4,"language":"urdu"}',
            200,
          ),
        ),
      );

      final result = await client.uploadReport(filePath);

      expect(result.id, 7);
      expect(result.text, 'Hemoglobin 13.2');
      expect(result.confidence, 91.5);
      expect(result.language, 'urdu');
      expect(result.isLowConfidence, isFalse);
    });

    // Regression for the reported bug: a cold Render edge answers a bare 503
    // (no FastAPI body) on the first upload after the free instance sleeps.
    // The client must retry that instead of surfacing "busy right now" as a
    // permanent failure the user cannot distinguish from a broken deploy.
    test(
      'retries a cold-start 503 and recovers when the service wakes',
      () async {
        var calls = 0;
        final client = clientWith(
          MockClient((_) async {
            calls++;
            if (calls == 1) return http.Response('', 503); // bare edge 503
            return http.Response(
              '{"id":1,"text":"ok","confidence":80,'
              '"skew_corrected_degrees":0,"language":"english"}',
              200,
            );
          }),
        );

        final result = await client.uploadReport(filePath);

        expect(result.text, 'ok');
        expect(calls, 2);
      },
    );

    // A 4xx is a real answer, not a blip. Retrying it only delays the error.
    test('does not retry a 4xx response', () async {
      var calls = 0;
      final client = clientWith(
        MockClient((_) async {
          calls++;
          return http.Response(
            '{"detail":"That file type is not supported."}',
            415,
          );
        }),
      );

      await expectLater(
        client.uploadReport(filePath),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
    });

    // Every attempt failing must still surface, not loop forever. A 503 with
    // no body maps to the busy wording that prompted this fix.
    test('gives up after the configured number of attempts', () async {
      var calls = 0;
      final client = clientWith(
        MockClient((_) async {
          calls++;
          return http.Response('', 503);
        }),
      );

      await expectLater(
        client.uploadReport(filePath),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Report scanning is busy right now. Please try again shortly.',
          ),
        ),
      );
      expect(calls, 3);
    });

    // A transport error (no status code) is retryable and must rebuild the
    // one-shot MultipartRequest body on each attempt.
    test('retries a transport failure and gives up cleanly', () async {
      var calls = 0;
      final client = clientWith(
        MockClient((_) async {
          calls++;
          throw http.ClientException('Connection reset by peer');
        }),
      );

      await expectLater(
        client.uploadReport(filePath),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', isNull),
        ),
      );
      expect(calls, 3);
    });
  });

  group('connection banner', () {
    Widget appWithClient(ApiClient client) {
      return signedInApp(
        overrides: [apiClientProvider.overrideWithValue(client)],
      );
    }

    testWidgets('shows Success state when the service is healthy', (
      tester,
    ) async {
      final client = ApiClient(
        baseUrl: 'http://localhost:8000',
        client: MockClient((_) async => http.Response('{"status":"ok"}', 200)),
      );

      await tester.pumpWidget(appWithClient(client));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check service connection'));
      await tester.tap(find.text('Check service connection'));
      await tester.pumpAndSettle();

      expect(find.text('Connected to the MedAIx service.'), findsOneWidget);
    });

    // The state machine must settle: a stuck spinner is a hard failure even
    // though the underlying error is handled.
    testWidgets('shows Error state and Try again when unreachable', (
      tester,
    ) async {
      final client = ApiClient(
        baseUrl: 'http://localhost:8000',
        client: MockClient((_) async {
          throw http.ClientException('Connection refused');
        }),
      );

      await tester.pumpWidget(appWithClient(client));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check service connection'));
      await tester.tap(find.text('Check service connection'));
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the MedAIx service.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Checking connection'), findsNothing);
    });
  });

  testWidgets('signed-out app asks for an email before signing in', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authGatewayProvider.overrideWithValue(FakeAuthGateway())],
        child: const MedAIxApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Please sign in to continue.'), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Email and password'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter the email address for your account.'),
      findsOneWidget,
    );
  });

  testWidgets('onboarding finishes by opening the report scanner', (
    tester,
  ) async {
    var profileReads = 0;
    await tester.pumpWidget(
      signedInApp(
        overrides: [
          profileProvider.overrideWith((ref) async {
            profileReads += 1;
            if (profileReads == 1) {
              return const PatientProfile(
                id: 1,
                name: null,
                age: null,
                weight: null,
                height: null,
                sex: null,
                conditions: '',
                medications: '',
                allergies: '',
                onboardingComplete: false,
              );
            }
            return _completeProfile;
          }),
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: 'http://localhost:8000',
              accessToken: () => 'token',
              client: MockClient(
                (_) async => http.Response(
                  '{"id":1,"name":"Ada","age":34,"weight":70,"height":170,'
                  '"sex":"female","conditions":"","medications":"",'
                  '"allergies":"","onboarding_complete":true}',
                  200,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('About you'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('profile-age')), '34');
    await tester.tap(find.text('Female'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Body measurements'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('profile-weight')), '70');
    await tester.enterText(find.byKey(const Key('profile-height')), '170');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Health background'), findsOneWidget);
    await tester.tap(find.text('Scan a report'));
    await tester.pumpAndSettle();

    expect(find.text('Report language'), findsOneWidget);
  });

  // ---- Sprint 2: simplified reports ----

  group('SimplifyReportScreen', () {
    const reportsJson =
        '[{"id":7,"uploaded_at":"2026-10-20T10:00:00","confidence":91.5,'
        '"has_simplified":false,"image_path":"cbc.png"},'
        '{"id":3,"uploaded_at":"2026-10-18T09:00:00","confidence":88.0,'
        '"has_simplified":true,"image_path":"lipids.pdf"}]';
    const simplifiedJson =
        '{"id":7,"original_text":"Glucose 98 mg/dL","simplified_text":'
        '"Blood sugar 98 milligrams per decilitre","terms_simplified":2,'
        '"sentence_count":1,"note":"2 medical terms reworded into plain language."}';

    Widget screen(MockClient mock) {
      return ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: 'http://localhost:8000',
              accessToken: () => 'token',
              client: mock,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const SimplifyReportScreen(),
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      );
    }

    testWidgets(
      'shows the empty state with a scan CTA when there are no reports',
      (tester) async {
        await tester.pumpWidget(
          screen(MockClient((_) async => http.Response('[]', 200))),
        );
        await tester.pumpAndSettle();

        expect(find.text('No reports yet'), findsOneWidget);
        expect(find.text('Scan a report'), findsOneWidget);
      },
    );

    testWidgets('lists reports newest first with Simplify and View actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        screen(MockClient((_) async => http.Response(reportsJson, 200))),
      );
      await tester.pumpAndSettle();

      expect(find.text('cbc.png'), findsOneWidget);
      expect(find.text('lipids.pdf'), findsOneWidget);
      expect(find.text('Simplify'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
      // Newest (cbc.png) is rendered above the older one.
      expect(
        tester.getTopLeft(find.text('cbc.png')).dy,
        lessThan(tester.getTopLeft(find.text('lipids.pdf')).dy),
      );
    });

    testWidgets('simplifying opens the result page with both views', (
      tester,
    ) async {
      await tester.pumpWidget(
        screen(
          MockClient((request) async {
            if (request.url.path == '/reports') {
              return http.Response(reportsJson, 200);
            }
            return http.Response(simplifiedJson, 200);
          }),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Simplify'));
      await tester.pumpAndSettle();

      expect(find.byType(SimplifiedReportPage), findsOneWidget);
      expect(find.text('Rewritten in plain language'), findsOneWidget);
      expect(
        find.text('Blood sugar 98 milligrams per decilitre'),
        findsOneWidget,
      );
      expect(find.text('2 terms reworded'), findsOneWidget);

      await tester.tap(find.text('Original text'));
      await tester.pumpAndSettle();
      expect(find.text('Glucose 98 mg/dL'), findsOneWidget);

      await tester.tap(find.text('Back to reports'));
      await tester.pumpAndSettle();
      expect(find.byType(SimplifyReportScreen), findsOneWidget);
    });

    testWidgets('a failed simplify shows the server message with Try again', (
      tester,
    ) async {
      var simplifyCalls = 0;
      await tester.pumpWidget(
        screen(
          MockClient((request) async {
            if (request.url.path == '/reports') {
              return http.Response(reportsJson, 200);
            }
            simplifyCalls++;
            return http.Response(
              '{"detail":"That report has no readable text to simplify."}',
              422,
            );
          }),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Simplify'));
      await tester.pumpAndSettle();

      expect(
        find.text('That report has no readable text to simplify.'),
        findsOneWidget,
      );
      // A 422 is final, so no retry is offered; Dismiss clears the banner.
      expect(find.text('Try again'), findsNothing);
      expect(simplifyCalls, 1);
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(
        find.text('That report has no readable text to simplify.'),
        findsNothing,
      );
    });

    testWidgets('a list failure shows a plain-language error with Try again', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        screen(
          MockClient((_) async {
            calls++;
            // 401 is not retried, so the first fetch fails outright.
            if (calls == 1) return http.Response('nope', 401);
            return http.Response('[]', 200);
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load your reports'), findsOneWidget);
      expect(find.text('Please sign in to continue.'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No reports yet'), findsOneWidget);
    });
  });

  group('ProfileScreen', () {
    testWidgets('shows stored values, validates, and confirms a save', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authGatewayProvider.overrideWithValue(
              FakeAuthGateway(session: _signedInSession),
            ),
            profileProvider.overrideWith((ref) async => _completeProfile),
            apiClientProvider.overrideWithValue(
              ApiClient(
                baseUrl: 'http://localhost:8000',
                accessToken: () => 'token',
                client: MockClient(
                  (_) async => http.Response(
                    '{"id":1,"name":"Test","age":31,"weight":70,"height":170,'
                    '"sex":"female","conditions":"","medications":"",'
                    '"allergies":"","onboarding_complete":true}',
                    200,
                  ),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('170'), findsOneWidget);

      final ageField = find.widgetWithText(TextField, 'Age');
      await tester.enterText(ageField, '0');
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an age from 1 to 120.'), findsOneWidget);

      await tester.enterText(ageField, '31');
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(find.text('Profile saved.'), findsOneWidget);
      expect(find.text('Enter an age from 1 to 120.'), findsNothing);
    });
  });
}
