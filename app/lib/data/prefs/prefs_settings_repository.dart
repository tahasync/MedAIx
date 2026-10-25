/// [SettingsRepository] backed by SharedPreferences.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/data/settings_repository.dart';

class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const String _theme = 'theme_mode';
  static const String _remMeds = 'reminder_medicines';
  static const String _remWater = 'reminder_water';
  static const String _remFollowUp = 'reminder_follow_up';
  static const String _onboardingSeen = 'onboarding_seen';

  @override
  Future<ThemeMode> loadThemeMode() async {
    final String? raw = await _prefs.getString(_theme);
    return ThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => ThemeMode.system,
    );
  }

  @override
  Future<void> saveThemeMode(ThemeMode mode) =>
      _prefs.setString(_theme, mode.name);

  @override
  Future<ReminderSettings> loadReminders() async {
    const ReminderSettings d = ReminderSettings();
    return ReminderSettings(
      medicines: await _prefs.getBool(_remMeds) ?? d.medicines,
      water: await _prefs.getBool(_remWater) ?? d.water,
      followUp: await _prefs.getBool(_remFollowUp) ?? d.followUp,
    );
  }

  @override
  Future<void> saveReminders(ReminderSettings s) async {
    await _prefs.setBool(_remMeds, s.medicines);
    await _prefs.setBool(_remWater, s.water);
    await _prefs.setBool(_remFollowUp, s.followUp);
  }

  @override
  Future<bool> loadOnboardingSeen() async =>
      await _prefs.getBool(_onboardingSeen) ?? false;

  @override
  Future<void> saveOnboardingSeen(bool seen) =>
      _prefs.setBool(_onboardingSeen, seen);
}
