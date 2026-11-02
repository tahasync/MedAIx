/// Fake repository implementation isolated by feature responsibility.
library;

import 'package:flutter/material.dart';
import '../../features/settings/data/settings_repository.dart';

/// Synthetic in-memory implementation for tests and local demos.
class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({
    this.themeMode = ThemeMode.system,
    this.reminders = const ReminderSettings(),
    this.onboardingSeen = false,
    this.hapticsEnabled = true,
  });

  ThemeMode themeMode;
  ReminderSettings reminders;
  bool onboardingSeen;
  bool hapticsEnabled;

  @override
  Future<ThemeMode> loadThemeMode() async => themeMode;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async => themeMode = mode;

  @override
  Future<ReminderSettings> loadReminders() async => reminders;

  @override
  Future<void> saveReminders(ReminderSettings settings) async =>
      reminders = settings;

  @override
  Future<bool> loadOnboardingSeen() async => onboardingSeen;

  @override
  Future<void> saveOnboardingSeen(bool seen) async => onboardingSeen = seen;

  @override
  Future<bool> loadHapticsEnabled() async => hapticsEnabled;

  @override
  Future<void> saveHapticsEnabled(bool enabled) async =>
      hapticsEnabled = enabled;
}

/// A reports repository that always fails, for error-state demos/tests.
