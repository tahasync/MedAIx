import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// System haptic cues, centralized so settings and tests control every event.
class AppHaptics {
  AppHaptics({this.enabled = true});

  bool enabled;
  DateTime? _lastCue;
  static const Duration _minimumInterval = Duration(milliseconds: 60);

  void tap() => _play(HapticFeedback.lightImpact);
  void select() => _play(HapticFeedback.selectionClick);
  void toggle() => _play(HapticFeedback.selectionClick);
  void confirm() => _play(HapticFeedback.mediumImpact);
  void success() => _play(HapticFeedback.mediumImpact);
  void warning() => _play(HapticFeedback.mediumImpact);
  void error() => _play(HapticFeedback.heavyImpact);
  void refresh() => _play(HapticFeedback.lightImpact);

  void _play(Future<void> Function() cue) {
    if (!enabled) return;
    final DateTime now = DateTime.now();
    final DateTime? previous = _lastCue;
    if (previous != null && now.difference(previous) < _minimumInterval) {
      return;
    }
    _lastCue = now;
    unawaited(cue());
  }
}

/// Riverpod service shared by widgets and feature controllers.
final appHapticsProvider = Provider<AppHaptics>(
  (ref) => AppHaptics(enabled: false),
);

/// Plays a cue from a callback without making shared design widgets stateful.
void playHaptic(BuildContext context, void Function(AppHaptics) cue) {
  final AppHaptics haptics = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(appHapticsProvider);
  cue(haptics);
}
