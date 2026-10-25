import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tahasync_medaix/data/api/api_client.dart';
import 'package:tahasync_medaix/features/wellness/data/api_wellness_repository.dart';
import 'package:tahasync_medaix/features/wellness/data/wellness_repository.dart';

void main() {
  group('ApiWellnessRepository', () {
    late _MemoryWellnessStore store;
    late DateTime now;

    setUp(() {
      store = _MemoryWellnessStore();
      now = DateTime(2026, 10, 26, 10);
    });

    test('loads and caches the server day', () async {
      final ApiWellnessRepository repository = _repository(
        store: store,
        clock: () => now,
        handler: (request) async => _ok(_day(water: 500)),
      );

      final WellnessDay result = await repository.today();

      expect(result.waterMl, 500);
      expect(result.isOffline, isFalse);
      expect((await store.readDay('user-1', '2026-10-26'))?.waterMl, 500);
    });

    test(
      'keeps an offline entry and replays it with the same client id',
      () async {
        bool online = false;
        final List<String> replayedIds = <String>[];
        final ApiWellnessRepository repository = _repository(
          store: store,
          clock: () => now,
          handler: (request) async {
            if (request.method == 'POST') {
              final Map<String, dynamic> entry =
                  jsonDecode(request.body) as Map<String, dynamic>;
              replayedIds.add(entry['client_id'] as String);
              if (!online) return _unavailable();
              return _ok(_day(water: 250));
            }
            if (!online) return _unavailable();
            return _ok(_day(water: 250));
          },
        );

        final WellnessDay offline = await repository.addWater(250);
        expect(offline.waterMl, 250);
        expect(offline.pendingSyncCount, 1);
        expect(offline.isOffline, isTrue);

        online = true;
        final WellnessDay synced = await repository.today();
        expect(synced.waterMl, 250);
        expect(synced.pendingSyncCount, 0);
        expect(synced.isOffline, isFalse);
        expect(replayedIds, hasLength(2));
        expect(replayedIds[0], replayedIds[1]);
      },
    );

    test(
      'does not convert authorization errors into offline entries',
      () async {
        final ApiWellnessRepository repository = _repository(
          store: store,
          clock: () => now,
          handler: (request) async => http.Response('{}', 401),
        );

        await expectLater(
          repository.addSteps(100),
          throwsA(isA<ApiException>()),
        );
        expect(await store.readPending('user-1'), isEmpty);
      },
    );

    test('clears only the selected account local data', () async {
      await store.writeDay('user-1', '2026-10-26', _wellnessDay(water: 500));
      await store.writeDay('user-2', '2026-10-26', _wellnessDay(water: 900));
      final ApiWellnessRepository repository = _repository(
        store: store,
        clock: () => now,
        handler: (request) async => _ok(_day()),
      );

      await repository.clearLocal();

      expect(await store.readDay('user-1', '2026-10-26'), isNull);
      expect((await store.readDay('user-2', '2026-10-26'))?.waterMl, 900);
    });
  });
}

ApiWellnessRepository _repository({
  required _MemoryWellnessStore store,
  required DateTime Function() clock,
  required Future<http.Response> Function(http.Request) handler,
}) => ApiWellnessRepository(
  ApiClient(baseUrl: 'https://example.test', client: MockClient(handler)),
  userId: 'user-1',
  localStore: store,
  clock: clock,
);

http.Response _ok(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _unavailable() => http.Response('{}', 503);

Map<String, Object?> _day({int water = 0}) => <String, Object?>{
  'date': '2026-10-26',
  'water_ml': water,
  'water_goal_ml': 2100,
  'water_goal_note': 'A starting estimate.',
  'steps': 0,
  'step_goal': 6000,
  'step_goal_note': 'A general starting goal.',
  'exercise_label': null,
  'exercise_minutes': 0,
  'daily_tip': 'Take small steps.',
};

WellnessDay _wellnessDay({int water = 0}) =>
    WellnessDay.fromJson(_day(water: water));

class _MemoryWellnessStore implements WellnessLocalStore {
  final Map<String, List<Map<String, dynamic>>> _pending = {};
  final Map<String, WellnessDay> _days = {};

  String _key(String userId, String day) => '$userId:$day';

  @override
  Future<void> clear(String userId) async {
    _pending.remove(userId);
    _days.removeWhere((key, value) => key.startsWith('$userId:'));
  }

  @override
  Future<WellnessDay?> readDay(String userId, String day) async =>
      _days[_key(userId, day)];

  @override
  Future<List<Map<String, dynamic>>> readPending(String userId) async =>
      List<Map<String, dynamic>>.of(_pending[userId] ?? const []);

  @override
  Future<void> writeDay(String userId, String day, WellnessDay value) async {
    _days[_key(userId, day)] = value;
  }

  @override
  Future<void> writePending(
    String userId,
    List<Map<String, dynamic>> entries,
  ) async {
    _pending[userId] = List<Map<String, dynamic>>.of(entries);
  }
}
