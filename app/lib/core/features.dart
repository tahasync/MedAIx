/// Sprint gating.
///
/// The UI layer was built ahead of the backend against the full mockup, but
/// `docs/roadmap.md` delivers one epic per sprint. [kBuildSprint] says which
/// sprint this build represents; everything from a later sprint is hidden
/// (no tab, no tile, no settings row) and its routes bounce to Home, so a
/// build only ever shows what has been delivered.
///
/// Build the current sprint (the default), or everything for a demo:
///
/// ```powershell
/// flutter run                                   # kBuildSprint = 5
/// flutter run --dart-define=MEDAIX_SPRINT=13    # every screen
/// ```
///
/// Screens read [featuresProvider]; tests override it to open gated screens.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The sprint this build is for. Bump it when a sprint's backend lands.
const int kBuildSprint = int.fromEnvironment('MEDAIX_SPRINT', defaultValue: 5);

/// A sprint number past the last one in the roadmap: everything enabled.
const int kAllSprints = 99;

/// Which epics are visible at a given sprint (numbers from the roadmap).
final class FeatureFlags {
  const FeatureFlags(this.sprint);

  /// Every feature on.
  const FeatureFlags.all() : sprint = kAllSprints;

  final int sprint;

  /// Sprint 3 — risk / trend analysis (`/reports/trends`, AI insight card).
  bool get trends => sprint >= 3;

  /// Sprint 4 — wellness tracking (Wellness tab, habit card on Home).
  bool get wellness => sprint >= 4;

  /// Sprint 9 — drug safety checker (Meds tab).
  bool get meds => sprint >= 9;

  /// Sprint 10 — medicine packet scanner (`/meds/scan`).
  bool get scan => sprint >= 10;

  /// Sprint 11 — doctor recommendation (`/doctor`).
  bool get doctorMatch => sprint >= 11;

  /// Sprint 12 — time-limited QR sharing (`/settings/share`).
  bool get share => sprint >= 12;

  /// Sprint 13 — doctor portal and reminders.
  bool get doctorPortal => sprint >= 13;
  bool get reminders => sprint >= 13;
}

/// The flags for this build. Override in tests to reach gated screens.
final featuresProvider = Provider<FeatureFlags>(
  (ref) => const FeatureFlags(kBuildSprint),
);
