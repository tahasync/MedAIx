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
    this.waterGoalNote = 'A starting estimate for today.',
    this.exerciseMinutes = 0,
    this.dailyTip = 'Small, steady habits can add up.',
    this.date,
    this.pendingSyncCount = 0,
    this.isOffline = false,
  });

  final int waterMl;

  /// Null means a clinician-set fluid limit takes precedence over estimates.
  final int? waterGoalMl;
  final int steps;
  final int stepGoal;

  /// null when nothing has been logged today.
  final String? exerciseLabel;

  /// e.g. "goal set for your condition".
  final String stepGoalNote;
  final String waterGoalNote;
  final int exerciseMinutes;
  final String dailyTip;
  final String? date;
  final int pendingSyncCount;
  final bool isOffline;

  double get waterProgress =>
      waterGoalMl == null || waterGoalMl == 0 ? 0 : waterMl / waterGoalMl!;
  double get stepProgress => stepGoal == 0 ? 0 : steps / stepGoal;

  /// 0–100. Water and steps count 40 each, exercise 20. If a fluid goal is
  /// intentionally hidden, the available habits are reweighted fairly.
  int get habitScore {
    double points = 0;
    double availableWeight = 0;
    if (waterGoalMl != null && waterGoalMl! > 0) {
      points += waterProgress.clamp(0.0, 1.0) * 40;
      availableWeight += 40;
    }
    if (stepGoal > 0) {
      points += stepProgress.clamp(0.0, 1.0) * 40;
      availableWeight += 40;
    }
    points += exerciseLabel == null ? 0 : 20;
    availableWeight += 20;
    return availableWeight == 0 ? 0 : (points / availableWeight * 100).round();
  }

  /// What would lift the score next, for the Home card subtitle.
  String get nextStep {
    if (waterGoalMl != null && waterProgress < 1) {
      final int target = (habitScore + 8).clamp(0, 100);
      return 'Log water to reach $target today';
    }
    if (exerciseLabel == null) return 'Log a walk to finish today';
    if (stepProgress < 1) return 'Keep walking to hit your step goal';
    return 'All habits done for today';
  }

  WellnessDay copyWith({
    int? waterMl,
    int? steps,
    String? exerciseLabel,
    int? exerciseMinutes,
    String? dailyTip,
    String? date,
    int? pendingSyncCount,
    bool? isOffline,
  }) {
    return WellnessDay(
      waterMl: waterMl ?? this.waterMl,
      waterGoalMl: waterGoalMl,
      steps: steps ?? this.steps,
      stepGoal: stepGoal,
      exerciseLabel: exerciseLabel ?? this.exerciseLabel,
      stepGoalNote: stepGoalNote,
      waterGoalNote: waterGoalNote,
      exerciseMinutes: exerciseMinutes ?? this.exerciseMinutes,
      dailyTip: dailyTip ?? this.dailyTip,
      date: date ?? this.date,
      pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
      isOffline: isOffline ?? this.isOffline,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'water_ml': waterMl,
    'water_goal_ml': waterGoalMl,
    'steps': steps,
    'step_goal': stepGoal,
    'exercise_label': exerciseLabel,
    'step_goal_note': stepGoalNote,
    'water_goal_note': waterGoalNote,
    'exercise_minutes': exerciseMinutes,
    'daily_tip': dailyTip,
    'date': date,
    'pending_sync_count': pendingSyncCount,
    'is_offline': isOffline,
  };

  factory WellnessDay.fromJson(Map<String, dynamic> json) => WellnessDay(
    waterMl: (json['water_ml'] as num?)?.toInt() ?? 0,
    waterGoalMl: (json['water_goal_ml'] as num?)?.toInt(),
    steps: (json['steps'] as num?)?.toInt() ?? 0,
    stepGoal: (json['step_goal'] as num?)?.toInt() ?? 6000,
    exerciseLabel: json['exercise_label'] as String?,
    stepGoalNote: json['step_goal_note'] as String? ?? 'Starting goal.',
    waterGoalNote:
        json['water_goal_note'] as String? ?? 'A starting estimate for today.',
    exerciseMinutes: (json['exercise_minutes'] as num?)?.toInt() ?? 0,
    dailyTip:
        json['daily_tip'] as String? ?? 'Small, steady habits can add up.',
    date: json['date'] as String?,
    pendingSyncCount: (json['pending_sync_count'] as num?)?.toInt() ?? 0,
    isOffline: json['is_offline'] as bool? ?? false,
  );
}

abstract class WellnessRepository {
  Future<WellnessDay> today();

  Future<WellnessDay> addWater(int ml);

  Future<WellnessDay> addSteps(int steps);

  Future<WellnessDay> logExercise(String label, {int minutes = 10});

  /// Removes this account's offline wellness data after a profile deletion.
  Future<void> clearLocal();
}
