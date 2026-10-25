/// Share-with-doctor session state, the duration picker, the doctor's
/// portal view and the clock the countdowns read (overridable in tests).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories.dart';
import '../../reports/data/reports_repository.dart';
import '../data/share_repository.dart';

/// Wall clock used by the countdowns. Tests override it with a fake so
/// expiry can be driven deterministically.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Plain-language message for an error; never the raw exception.
String friendlyShareError(Object error, String fallback) =>
    error is RepositoryException ? error.message : fallback;

/// Durations offered, in minutes (mockup chips).
const List<int> kShareDurations = <int>[15, 30, 60];

/// The default selection in the picker.
const int kDefaultShareMinutes = 30;

/// Single-select duration for the next code.
class ShareDurationController extends Notifier<int> {
  @override
  int build() => kDefaultShareMinutes;

  void select(int minutes) => state = minutes;
}

final shareDurationProvider = NotifierProvider<ShareDurationController, int>(
  ShareDurationController.new,
);

/// The active code, or `null` when there is none. Create / revoke keep
/// the previous value while in flight (`isLoading` drives button spinners)
/// and surface failures as an error state with the previous value kept.
class ShareController extends AsyncNotifier<ShareSession?> {
  @override
  Future<ShareSession?> build() => ref.watch(shareRepositoryProvider).active();

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(shareRepositoryProvider).active(),
    );
  }

  Future<ShareSession?> create(int minutes) async {
    state = const AsyncLoading<ShareSession?>().copyWithPrevious(state);
    try {
      final ShareSession session = await ref
          .read(shareRepositoryProvider)
          .create(minutes: minutes);
      state = AsyncData<ShareSession?>(session);
      return session;
    } on Exception catch (error, stack) {
      state = AsyncError<ShareSession?>(error, stack).copyWithPrevious(state);
      return null;
    }
  }

  Future<bool> revoke() async {
    state = const AsyncLoading<ShareSession?>().copyWithPrevious(state);
    try {
      await ref.read(shareRepositoryProvider).revoke();
      state = const AsyncData<ShareSession?>(null);
      return true;
    } on Exception catch (error, stack) {
      state = AsyncError<ShareSession?>(error, stack).copyWithPrevious(state);
      return false;
    }
  }

  /// The countdown reached zero on this device.
  void expire() {
    if (state.valueOrNull != null) state = const AsyncData<ShareSession?>(null);
  }
}

final shareProvider = AsyncNotifierProvider<ShareController, ShareSession?>(
  ShareController.new,
);

/// What the doctor sees for [code]. Errors when the code is unknown,
/// expired or revoked.
final doctorPortalProvider = FutureProvider.autoDispose
    .family<DoctorPortalView, String>(
      (ref, code) => ref.watch(shareRepositoryProvider).portalView(code),
    );
