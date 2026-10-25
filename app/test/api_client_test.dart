/// Unit tests for the HTTP layer: retry, timeout and error wrapping. Ported
/// unchanged from the Sprint 2 suite; only the import path moved.
library;

import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tahasync_medaix/data/api/api_client.dart';

void main() {
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
}
