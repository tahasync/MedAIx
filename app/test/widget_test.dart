import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tahasync_medaix/main.dart';
import 'package:tahasync_medaix/src/api_client.dart';
import 'package:tahasync_medaix/src/providers.dart';
import 'package:tahasync_medaix/src/theme.dart';

void main() {
  testWidgets('app boots and shows the MedAIx placeholder', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MedAIxApp()));
    await tester.pumpAndSettle();

    expect(find.text('MedAIx'), findsWidgets);
    expect(find.text('Smarter care. Better lives.'), findsOneWidget);
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
    expect(AppTheme.light.scaffoldBackgroundColor, isNot(const Color(0xFFFFFFFF)));
    expect(AppTheme.dark.scaffoldBackgroundColor, isNot(const Color(0xFF000000)));
  });

  testWidgets('app renders under a forced dark theme', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const ProviderScope(child: MedAIxApp()));
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.text('Smarter care. Better lives.'));
    expect(Theme.of(context).colorScheme.brightness, Brightness.dark);
  });

  group('ApiClient.checkHealth', () {
    ApiClient clientWith(MockClient mock) =>
        ApiClient(baseUrl: 'http://localhost:8000', client: mock);

    test('returns true for a healthy service', () async {
      final client = clientWith(MockClient(
        (_) async => http.Response('{"status":"ok"}', 200),
      ));

      expect(await client.checkHealth(), isTrue);
    });

    test('throws ApiException on a non-200 response', () async {
      final client = clientWith(MockClient(
        (_) async => http.Response('{"status":"degraded"}', 503),
      ));

      expect(client.checkHealth(), throwsA(isA<ApiException>()));
    });

    // Regression: the http package reports a refused connection as
    // ClientException, which is not a SocketException. Missing this left the
    // UI's Loading state spinning forever on a dead backend.
    test('wraps a refused connection (ClientException) in ApiException', () async {
      final client = clientWith(MockClient((_) async {
        throw http.ClientException('Connection closed before full header');
      }));

      expect(
        client.checkHealth(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.error, 'error', isA<http.ClientException>()),
        ),
      );
    });

    test('wraps an expired deadline (TimeoutException) in ApiException', () async {
      final client = clientWith(MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 30));
        return http.Response('{"status":"ok"}', 200);
      }));

      expect(client.checkHealth(), throwsA(isA<ApiException>()));
    });

    // ApiException raised for a non-200 must not be re-wrapped, or callers
    // lose the status code they branch on.
    test('does not re-wrap ApiException', () async {
      final client = clientWith(MockClient(
        (_) async => http.Response('nope', 500),
      ));

      await expectLater(
        client.checkHealth(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });
  });

  group('connection banner', () {
    Widget appWithClient(ApiClient client) {
      return ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(client)],
        child: const MedAIxApp(),
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
      await tester.tap(find.text('Check connection'));
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
      await tester.tap(find.text('Check connection'));
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the MedAIx service.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Checking connection'), findsNothing);
    });
  });
}