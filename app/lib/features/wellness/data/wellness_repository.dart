/// Daily habits: water, steps, exercise, and the habit score shown on Home.
library;

class WellnessDay {
  const WellnessDay({
    required this.waterMl,
    required this.waterGoalMl,
    required this.steps,
    required this.stepGoal,
    required this.exerciseLabel,
    required this.stepGoalNote,
  });

  final int waterMl;
  final int waterGoalMl;
  final int steps;
  final int stepGoal;

  /// null when nothing has been logged today.
  final String? exerciseLabel;

  /// e.g. "goal set for your condition".
  final String stepGoalNote;

  double get waterProgress => waterGoalMl == 0 ? 0 : waterMl / waterGoalMl;
  double get stepProgress => stepGoal == 0 ? 0 : steps / stepGoal;

  /// 0–100. Water and steps count 40 each, exercise 20.
  int get habitScore {
    final double water = waterProgress.clamp(0.0, 1.0) * 40;
    final double stepsScore = stepProgress.clamp(0.0, 1.0) * 40;
    final double exercise = exerciseLabel == null ? 0 : 20;
    return (water + stepsScore + exercise).round();
  }

  /// What would lift the score next, for the Home card subtitle.
  String get nextStep {
    if (waterProgress < 1) {
      final int target = (habitScore + 8).clamp(0, 100);
      return 'Log water to reach $target today';
    }
    if (exerciseLabel == null) return 'Log a walk to finish today';
    if (stepProgress < 1) return 'Keep walking to hit your step goal';
    return 'All habits done for today';
  }

  WellnessDay copyWith({int? waterMl, int? steps, String? exerciseLabel}) {
    return WellnessDay(
      waterMl: waterMl ?? this.waterMl,
      waterGoalMl: waterGoalMl,
      steps: steps ?? this.steps,
      stepGoal: stepGoal,
      exerciseLabel: exerciseLabel ?? this.exerciseLabel,
      stepGoalNote: stepGoalNote,
    );
  }
}

abstract class WellnessRepository {
  Future<WellnessDay> today();

  Future<WellnessDay> addWater(int ml);

  Future<WellnessDay> logExercise(String label);
}
