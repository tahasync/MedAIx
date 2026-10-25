/// Today's habits (water, steps, exercise) and the habit score.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories.dart';
import '../../reports/data/reports_repository.dart';
import '../data/wellness_repository.dart';

/// Plain-language message for an error; never the raw exception.
String friendlyWellnessError(Object error, String fallback) =>
    error is RepositoryException ? error.message : fallback;

/// Today's log. Mutations keep the current data on screen (no flicker to
/// a skeleton) and return `true` on success, `false` on failure, or `null`
/// when ignored because another change is still in flight.
class WellnessController extends AsyncNotifier<WellnessDay> {
  bool _pending = false;

  @override
  Future<WellnessDay> build() => ref.watch(wellnessRepositoryProvider).today();

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(wellnessRepositoryProvider).today(),
    );
  }

  Future<bool?> addWater(int ml) => _mutate((repo) => repo.addWater(ml));

  Future<bool?> logExercise(String label) =>
      _mutate((repo) => repo.logExercise(label));

  Future<bool?> _mutate(
    Future<WellnessDay> Function(WellnessRepository repo) action,
  ) async {
    if (_pending) return null;
    _pending = true;
    try {
      state = AsyncData(await action(ref.read(wellnessRepositoryProvider)));
      return true;
    } on Exception {
      return false;
    } finally {
      _pending = false;
    }
  }
}

final wellnessProvider = AsyncNotifierProvider<WellnessController, WellnessDay>(
  WellnessController.new,
);
