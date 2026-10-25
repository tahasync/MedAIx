/// Device-local preferences: theme mode and reminder switches. Persisted in
/// SharedPreferences; the fake keeps them in memory for tests.
library;

import 'package:flutter/material.dart';

class ReminderSettings {
  const ReminderSettings({
    this.medicines = true,
    this.water = true,
    this.followUp = false,
  });

  final bool medicines;
  final bool water;
  final bool followUp;

  ReminderSettings copyWith({bool? medicines, bool? water, bool? followUp}) {
    return ReminderSettings(
      medicines: medicines ?? this.medicines,
      water: water ?? this.water,
      followUp: followUp ?? this.followUp,
    );
  }
}

abstract class SettingsRepository {
  Future<ThemeMode> loadThemeMode();

  Future<void> saveThemeMode(ThemeMode mode);

  Future<ReminderSettings> loadReminders();

  Future<void> saveReminders(ReminderSettings settings);

  /// True once onboarding has been skipped or finished on this device, so
  /// "Skip for now" is remembered even before the profile is saved.
  Future<bool> loadOnboardingSeen();

  Future<void> saveOnboardingSeen(bool seen);
}
