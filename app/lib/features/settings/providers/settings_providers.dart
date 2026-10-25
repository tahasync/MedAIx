/// Theme mode, reminder switches and the onboarding-seen flag, persisted
/// through [SettingsRepository].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories.dart';
import '../data/settings_repository.dart';

/// System / Light / Dark, user-selectable in More. Starts on System and
/// restores the saved choice as soon as the repository answers.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final repo = ref.watch(settingsRepositoryProvider);
    bool disposed = false;
    ref.onDispose(() => disposed = true);
    repo.loadThemeMode().then((mode) {
      if (!disposed) state = mode;
    }).ignore();
    return ThemeMode.system;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref.read(settingsRepositoryProvider).saveThemeMode(mode);
  }

  /// The "Dark appearance" switch: on = dark, off = light. Both override
  /// System; "Follow system" is offered separately.
  Future<void> setDark(bool dark) =>
      setMode(dark ? ThemeMode.dark : ThemeMode.light);
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class RemindersController extends AsyncNotifier<ReminderSettings> {
  @override
  Future<ReminderSettings> build() =>
      ref.watch(settingsRepositoryProvider).loadReminders();

  Future<void> save(ReminderSettings next) async {
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).saveReminders(next);
  }
}

final remindersProvider =
    AsyncNotifierProvider<RemindersController, ReminderSettings>(
      RemindersController.new,
    );

/// True once the user has skipped or finished onboarding on this device.
class OnboardingSeenController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.watch(settingsRepositoryProvider).loadOnboardingSeen();

  Future<void> markSeen() async {
    state = const AsyncData(true);
    await ref.read(settingsRepositoryProvider).saveOnboardingSeen(true);
  }
}

final onboardingSeenProvider =
    AsyncNotifierProvider<OnboardingSeenController, bool>(
      OnboardingSeenController.new,
    );
