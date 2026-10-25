/// FastAPI-backed wellness totals with a small per-account offline outbox.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/api/api_client.dart';
import 'wellness_repository.dart';

abstract interface class WellnessLocalStore {
  Future<List<Map<String, dynamic>>> readPending(String userId);

  Future<void> writePending(String userId, List<Map<String, dynamic>> entries);

  Future<WellnessDay?> readDay(String userId, String day);

  Future<void> writeDay(String userId, String day, WellnessDay value);

  Future<void> clear(String userId);
}

class SharedPreferencesWellnessStore implements WellnessLocalStore {
  SharedPreferencesWellnessStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  String _pendingKey(String userId) => 'wellness.v1.$userId.pending';

  String _dayKey(String userId, String day) => 'wellness.v1.$userId.day.$day';

  @override
  Future<List<Map<String, dynamic>>> readPending(String userId) async {
    final String? raw = await _preferences.getString(_pendingKey(userId));
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) return <Map<String, dynamic>>[];
    return decoded.whereType<Map<String, dynamic>>().toList(growable: true);
  }

  @override
  Future<void> writePending(
    String userId,
    List<Map<String, dynamic>> entries,
  ) => _preferences.setString(_pendingKey(userId), jsonEncode(entries));

  @override
  Future<WellnessDay?> readDay(String userId, String day) async {
    final String? raw = await _preferences.getString(_dayKey(userId, day));
    if (raw == null || raw.isEmpty) return null;
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return WellnessDay.fromJson(decoded);
  }

  @override
  Future<void> writeDay(String userId, String day, WellnessDay value) =>
      _preferences.setString(_dayKey(userId, day), jsonEncode(value.toJson()));

  @override
  Future<void> clear(String userId) async {
    final Set<String> keys = await _preferences.getKeys();
    final String prefix = 'wellness.v1.$userId.';
    for (final String key in keys.where((key) => key.startsWith(prefix))) {
      await _preferences.remove(key);
    }
  }
}

class ApiWellnessRepository implements WellnessRepository {
  ApiWellnessRepository(
    this._api, {
    required this.userId,
    WellnessLocalStore? localStore,
    DateTime Function()? clock,
  }) : _localStore = localStore ?? SharedPreferencesWellnessStore(),
       _clock = clock ?? DateTime.now;

  final ApiClient _api;
  final String userId;
  final WellnessLocalStore _localStore;
  final DateTime Function() _clock;
  int _idCounter = 0;

  @override
  Future<WellnessDay> today() async {
    final DateTime now = _clock();
    final String date = _formatDay(now);
    final int offset = now.timeZoneOffset.inMinutes;
    await _flushPending();
    try {
      final WellnessDay fresh = WellnessDay.fromJson(
        await _api.fetchWellnessDay(day: now, timezoneOffsetMinutes: offset),
      );
      await _localStore.writeDay(userId, date, fresh);
      return await _withPending(fresh, date, isOffline: false);
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) rethrow;
      final WellnessDay cached =
          await _localStore.readDay(userId, date) ?? _emptyDay(date);
      return await _withPending(cached, date, isOffline: true);
    }
  }

  @override
  Future<WellnessDay> addWater(int ml) => _record('water', ml);

  @override
  Future<WellnessDay> addSteps(int steps) => _record('steps', steps);

  @override
  Future<WellnessDay> logExercise(String label, {int minutes = 10}) =>
      _record('exercise', minutes, label: label);

  Future<WellnessDay> _record(String type, int value, {String? label}) async {
    final DateTime now = _clock();
    final int offset = now.timeZoneOffset.inMinutes;
    final String date = _formatDay(now);
    final String clientId =
        '$userId-${now.microsecondsSinceEpoch}-${_idCounter++}';
    final Map<String, dynamic> entry = <String, dynamic>{
      'client_id': clientId,
      'type': type,
      'value': value,
      'occurred_at': now.toUtc().toIso8601String(),
      'timezone_offset_minutes': offset,
      'label': ?label,
    };

    final List<Map<String, dynamic>> queue = await _localStore.readPending(
      userId,
    );
    queue.add(entry);
    await _localStore.writePending(userId, queue);

    final WellnessDay base =
        await _localStore.readDay(userId, date) ?? _emptyDay(date);
    final WellnessDay optimistic = await _withPending(
      base,
      date,
      isOffline: true,
    );

    try {
      final WellnessDay saved = WellnessDay.fromJson(
        await _api.createWellnessLog(entry),
      );
      final List<Map<String, dynamic>> remaining =
          await _localStore.readPending(userId)
            ..removeWhere((item) => item['client_id'] == clientId);
      await _localStore.writePending(userId, remaining);
      await _localStore.writeDay(userId, date, saved);
      return await _withPending(saved, date, isOffline: false);
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) {
        final List<Map<String, dynamic>> remaining =
            await _localStore.readPending(userId)
              ..removeWhere((item) => item['client_id'] == clientId);
        await _localStore.writePending(userId, remaining);
        rethrow;
      }
      return optimistic;
    }
  }

  Future<void> _flushPending() async {
    final List<Map<String, dynamic>> queue = await _localStore.readPending(
      userId,
    );
    if (queue.isEmpty) return;
    final List<Map<String, dynamic>> remaining = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> entry in queue) {
      try {
        final WellnessDay saved = WellnessDay.fromJson(
          await _api.createWellnessLog(Map<String, Object?>.from(entry)),
        );
        await _localStore.writeDay(userId, _entryDay(entry), saved);
      } on ApiException {
        remaining.add(entry);
      }
    }
    await _localStore.writePending(userId, remaining);
  }

  Future<WellnessDay> _withPending(
    WellnessDay base,
    String day, {
    required bool isOffline,
  }) {
    // Keep the server-confirmed snapshot as the cache baseline. Pending entries
    // are overlaid only for display and applied again after a restart.
    return _overlayEntries(base, day, isOffline: isOffline);
  }

  Future<WellnessDay> _overlayEntries(
    WellnessDay base,
    String day, {
    required bool isOffline,
  }) {
    return _localStore.readPending(userId).then((entries) {
      final List<Map<String, dynamic>> todays = entries
          .where((entry) => _entryDay(entry) == day)
          .toList();
      int water = base.waterMl;
      int steps = base.steps;
      int minutes = base.exerciseMinutes;
      String? exercise = base.exerciseLabel;
      for (final Map<String, dynamic> entry in todays) {
        final int value = (entry['value'] as num).toInt();
        switch (entry['type']) {
          case 'water':
            water += value;
            break;
          case 'steps':
            steps += value;
            break;
          case 'exercise':
            minutes += value;
            exercise = entry['label'] as String? ?? 'Exercise';
            break;
        }
      }
      return base.copyWith(
        waterMl: water,
        steps: steps,
        exerciseLabel: exercise,
        exerciseMinutes: minutes,
        date: day,
        pendingSyncCount: entries.length,
        isOffline: isOffline || todays.isNotEmpty,
      );
    });
  }

  String _entryDay(Map<String, dynamic> entry) {
    final DateTime utc = DateTime.parse(entry['occurred_at'] as String).toUtc();
    final int offset = (entry['timezone_offset_minutes'] as num).toInt();
    return _formatDay(utc.add(Duration(minutes: offset)));
  }

  WellnessDay _emptyDay(String date) => WellnessDay(
    waterMl: 0,
    waterGoalMl: null,
    steps: 0,
    stepGoal: 0,
    exerciseLabel: null,
    stepGoalNote: 'Your step goal loads when you reconnect.',
    waterGoalNote: 'Your hydration estimate loads when you reconnect.',
    dailyTip:
        'Entries are saved on this device and will sync when you reconnect.',
    date: date,
    isOffline: true,
  );

  String _formatDay(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  @override
  Future<void> clearLocal() => _localStore.clear(userId);
}
