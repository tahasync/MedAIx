/// Sprint 3: `GET /risk-trends` → domain models. Covers the JSON mapping,
/// the one-request-feeds-three-readers cache, and error wrapping.
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tahasync_medaix/data/api/api_client.dart';
import 'package:tahasync_medaix/data/api/api_insights_repository.dart';
import 'package:tahasync_medaix/features/home/data/insights_repository.dart';
import 'package:tahasync_medaix/features/reports/data/report_models.dart';
import 'package:tahasync_medaix/features/reports/data/reports_repository.dart';

const Map<String, dynamic> _sample = <String, dynamic>{
  'reports_count': 3,
  'needs_reports': false,
  'generated_at': '2026-10-25T16:00:00',
  'focus_markers': <String>['HbA1c', 'Fasting glucose'],
  'insight': <String, dynamic>{
    'marker': 'HbA1c',
    'title': 'Your HbA1c has risen across 3 reports',
    'body': '5.9 in March to 6.4 now. Worth raising with your doctor.',
  },
  'trends': <Map<String, dynamic>>[
    <String, dynamic>{
      'marker': 'HbA1c',
      'unit': '%',
      'focus': true,
      'range': <String, dynamic>{
        'low': 4.0,
        'high': 6.0,
        'label': 'Normal range 4.0–6.0 %',
        'source': 'default',
      },
      'direction': 'rising',
      'points': <Map<String, dynamic>>[
        <String, dynamic>{
          'report_id': 1,
          'date': '2026-03-02',
          'label': 'Mar',
          'value': 5.9,
          'status': 'ok',
        },
        <String, dynamic>{
          'report_id': 2,
          'date': '2026-06-10',
          'label': 'Jun',
          'value': 6.1,
          'status': 'warn',
        },
        <String, dynamic>{
          'report_id': 3,
          'date': '2026-10-20',
          'label': 'Oct',
          'value': 6.4,
          'status': 'error',
        },
      ],
      'alert': <String, dynamic>{
        'level': 'error',
        'code': 'rising_streak',
        'title': 'Rising 3 times in a row',
        'body':
            'Three readings up in a row usually means a change worth '
            'discussing.',
      },
    },
    <String, dynamic>{
      'marker': 'HDL',
      'unit': 'mg/dL',
      'focus': false,
      'range': <String, dynamic>{
        'low': 40,
        'high': null,
        'label': 'Normal range 40 mg/dL and above',
        'source': 'default',
      },
      'direction': 'stable',
      'points': <Map<String, dynamic>>[
        <String, dynamic>{
          'report_id': 3,
          'date': '2026-10-20',
          'label': 'Oct',
          'value': 52,
          'status': 'ok',
        },
      ],
      'alert': null,
    },
  ],
};

ApiInsightsRepository _repo(
  Future<http.Response> Function(http.Request) handler, {
  DateTime Function()? now,
}) => ApiInsightsRepository(
  ApiClient(baseUrl: 'http://localhost:8000', client: MockClient(handler)),
  now: now,
);

/// A JSON response the way FastAPI sends it (UTF-8, `application/json`).
http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: const <String, String>{'content-type': 'application/json'},
);

void main() {
  group('trendOverviewFromJson', () {
    test('maps every field the screens read', () {
      final TrendOverview o = trendOverviewFromJson(_sample);

      expect(o.reportsCount, 3);
      expect(o.needsReports, isFalse);
      expect(o.insight?.marker, 'HbA1c');
      expect(o.trends, hasLength(2));

      final MarkerTrend hba1c = o.trends.first;
      expect(hba1c.focus, isTrue);
      expect(hba1c.direction, TrendDirection.rising);
      expect(hba1c.latestStatus, ValueStatus.error);
      expect(hba1c.pointCount, 3);
      expect(hba1c.hasAlert, isTrue);
      expect(hba1c.series.threshold, 6.0);
      expect(hba1c.series.rangeLabel, '3 reports · Mar to Oct');
      expect(hba1c.series.alertTitle, 'Rising 3 times in a row');
      expect(hba1c.series.points.map((p) => p.value), <double>[5.9, 6.1, 6.4]);
      expect(hba1c.series.points.map((p) => p.label), <String>[
        'Mar',
        'Jun',
        'Oct',
      ]);
    });

    test('an open-ended range draws the lower limit; one point, no alert', () {
      final MarkerTrend hdl = trendOverviewFromJson(_sample).trends.last;

      expect(hdl.series.threshold, 40);
      expect(hdl.series.rangeLabel, '1 report so far');
      expect(hdl.hasAlert, isFalse);
      expect(hdl.direction, TrendDirection.stable);
      expect(hdl.latestStatus, ValueStatus.ok);
    });

    test('tolerates a minimal payload', () {
      final TrendOverview o = trendOverviewFromJson(<String, dynamic>{
        'reports_count': 0,
        'needs_reports': true,
        'trends': <dynamic>[],
      });

      expect(o.needsReports, isTrue);
      expect(o.insight, isNull);
      expect(o.trends, isEmpty);
    });

    test('byMarker ignores case and spacing', () {
      final TrendOverview o = trendOverviewFromJson(_sample);
      expect(o.byMarker('hba1c')?.marker, 'HbA1c');
      expect(o.byMarker('H b A 1 c')?.marker, 'HbA1c');
      expect(o.byMarker('Ferritin'), isNull);
    });
  });

  group('ApiInsightsRepository', () {
    test('one request feeds the insight, the overview and a chart', () async {
      int calls = 0;
      final repo = _repo((req) async {
        calls++;
        expect(req.url.path, '/risk-trends');
        return _json(_sample);
      });

      final Insight? insight = await repo.homeInsight();
      final TrendOverview overview = await repo.overview();
      final TrendSeries? series = await repo.trend(marker: 'HbA1c');

      expect(insight?.title, 'Your HbA1c has risen across 3 reports');
      expect(overview.trends, hasLength(2));
      expect(series?.marker, 'HbA1c');
      expect(calls, 1);
    });

    test('without a marker, opens on the insight’s marker', () async {
      final repo = _repo((_) async => _json(_sample));
      expect((await repo.trend())?.marker, 'HbA1c');
    });

    test('an unknown marker is null; nothing tracked is null', () async {
      final repo = _repo((_) async => _json(_sample));
      expect(await repo.trend(marker: 'Ferritin'), isNull);

      final empty = _repo(
        (_) async => _json(<String, dynamic>{
          'reports_count': 1,
          'needs_reports': true,
          'trends': <dynamic>[],
        }),
      );
      expect(await empty.trend(), isNull);
      expect(await empty.homeInsight(), isNull);
    });

    test('refetches once the cache window has passed', () async {
      int calls = 0;
      DateTime clock = DateTime(2026, 10, 25, 16);
      final repo = _repo((_) async {
        calls++;
        return _json(_sample);
      }, now: () => clock);

      await repo.overview();
      clock = clock.add(const Duration(seconds: 5));
      await repo.overview();
      expect(calls, 1);

      clock = clock.add(const Duration(seconds: 30));
      await repo.overview();
      expect(calls, 2);

      repo.invalidate();
      await repo.overview();
      expect(calls, 3);
    });

    test('wraps server errors as RepositoryException with its detail', () {
      final repo = _repo(
        (_) async => _json(<String, String>{
          'detail': 'Please sign in to continue.',
        }, 401),
      );

      expect(
        repo.overview(),
        throwsA(
          isA<RepositoryException>()
              .having(
                (e) => e.message,
                'message',
                'Please sign in to continue.',
              )
              .having((e) => e.canRetry, 'canRetry', isFalse),
        ),
      );
    });

    // A malformed body has no status code, so the client retries it like a
    // transient failure; drive the retry delays with a fake clock.
    test('a non-object body is an unexpected-response error', () {
      fakeAsync((async) {
        final repo = _repo((_) async => http.Response('[]', 200));
        Object? caught;
        unawaited(
          repo.overview().then<void>(
            (_) {},
            onError: (Object e) {
              caught = e;
            },
          ),
        );
        async.elapse(const Duration(seconds: 15));

        expect(
          caught,
          isA<RepositoryException>().having(
            (e) => e.message,
            'message',
            'The service returned an unexpected response.',
          ),
        );
      });
    });
  });
}
