/// Fake repository implementation isolated by feature responsibility.
library;

import '../../features/wellness/data/wellness_repository.dart';

/// Synthetic in-memory implementation for tests and local demos.
class FakeWellnessRepository implements WellnessRepository {
  FakeWellnessRepository({
    this.latency = const Duration(milliseconds: 200),
    WellnessDay? seed,
  }) : _day =
           seed ??
           const WellnessDay(
             waterMl: 750,
             waterGoalMl: 2400,
             steps: 4120,
             stepGoal: 6000,
             exerciseLabel: null,
             stepGoalNote: 'goal set for your condition',
           );

  final Duration latency;
  WellnessDay _day;

  @override
  Future<WellnessDay> today() async {
    await Future<void>.delayed(latency);
    return _day;
  }

  @override
  Future<WellnessDay> addWater(int ml) async {
    await Future<void>.delayed(latency);
    final int next = _day.waterMl + ml;
    _day = _day.copyWith(waterMl: next);
    return _day;
  }

  @override
  Future<WellnessDay> addSteps(int steps) async {
    await Future<void>.delayed(latency);
    _day = _day.copyWith(steps: _day.steps + steps);
    return _day;
  }

  @override
  Future<WellnessDay> logExercise(String label, {int minutes = 10}) async {
    await Future<void>.delayed(latency);
    _day = _day.copyWith(
      exerciseLabel: label,
      exerciseMinutes: _day.exerciseMinutes + minutes,
    );
    return _day;
  }

  @override
  Future<void> clearLocal() async {
    _day = const WellnessDay(
      waterMl: 0,
      waterGoalMl: 2400,
      steps: 0,
      stepGoal: 6000,
      exerciseLabel: null,
      stepGoalNote: 'general starting goal',
    );
  }
}
