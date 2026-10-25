/// Medicines list, interaction check and packet-scanner state. Screens
/// read these; nothing here touches the API client directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories.dart';
import '../../reports/data/reports_repository.dart';
import '../data/meds_repository.dart';

/// The mockup disables "Add another medicine" at three items.
const int kMaxMedicines = 3;

/// Plain-language message for an error; never the raw exception.
String friendlyError(Object error, String fallback) =>
    error is RepositoryException ? error.message : fallback;

/// The medicines the patient takes. Mutations return `true` on success so
/// the screen can toast; any failure leaves the list as it was.
class MedsController extends AsyncNotifier<List<Medicine>> {
  @override
  Future<List<Medicine>> build() => ref.watch(medsRepositoryProvider).list();

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(medsRepositoryProvider).list(),
    );
  }

  Future<bool> add(String name) async {
    final MedsRepository repo = ref.read(medsRepositoryProvider);
    try {
      await repo.add(name.trim());
      state = AsyncData(await repo.list());
      ref.read(interactionCheckProvider.notifier).clear();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<bool> remove(int id) async {
    final MedsRepository repo = ref.read(medsRepositoryProvider);
    try {
      await repo.remove(id);
      state = AsyncData(await repo.list());
      ref.read(interactionCheckProvider.notifier).clear();
      return true;
    } on Exception {
      return false;
    }
  }
}

final medsProvider = AsyncNotifierProvider<MedsController, List<Medicine>>(
  MedsController.new,
);

/// Result of the last "Check interactions": `null` data means the list has
/// not been checked since it last changed.
class InteractionCheckController
    extends Notifier<AsyncValue<List<InteractionWarning>?>> {
  @override
  AsyncValue<List<InteractionWarning>?> build() => const AsyncData(null);

  Future<void> run() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(medsRepositoryProvider).checkInteractions(),
    );
  }

  void clear() => state = const AsyncData(null);
}

final interactionCheckProvider =
    NotifierProvider<
      InteractionCheckController,
      AsyncValue<List<InteractionWarning>?>
    >(InteractionCheckController.new);

/// Names offered in the add sheet. Re-fetched whenever the list changes so
/// medicines already added drop out.
final medSuggestionsProvider = FutureProvider.autoDispose<List<String>>((ref) {
  ref.watch(medsProvider);
  return ref.watch(medsRepositoryProvider).suggestions();
});

/// Set by the scanner's "Type the name instead" so the Meds screen opens
/// its add sheet as soon as it is shown. Consumed (reset) when opened.
class MedsAddSheetRequest extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  void consume() => state = false;
}

final medsAddSheetRequestProvider = NotifierProvider<MedsAddSheetRequest, bool>(
  MedsAddSheetRequest.new,
);

/// Where the scanner is. Camera permission is modelled as state here — no
/// camera plugin is wired up yet.
enum ScanStep {
  /// Explain why we need the camera, offer typing instead.
  permission,

  /// Viewfinder with the sweep line; "Capture packet".
  scanning,

  /// A packet was read and matched.
  matched,

  /// The packet could not be read.
  failed,
}

class ScanState {
  const ScanState({
    this.step = ScanStep.permission,
    this.busy = false,
    this.result,
    this.errorMessage,
  });

  final ScanStep step;

  /// True while capturing or while adding the match to the list.
  final bool busy;
  final ScanResult? result;
  final String? errorMessage;
}

class ScanController extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanState();

  void allowCamera() => state = const ScanState(step: ScanStep.scanning);

  Future<void> capture() async {
    if (state.busy) return;
    state = const ScanState(step: ScanStep.scanning, busy: true);
    try {
      final ScanResult result = await ref
          .read(medsRepositoryProvider)
          .scanPacket();
      state = ScanState(step: ScanStep.matched, result: result);
    } on Exception catch (error) {
      state = ScanState(
        step: ScanStep.failed,
        errorMessage: friendlyError(
          error,
          'The packet was too blurry to read the name.',
        ),
      );
    }
  }

  /// Back to the viewfinder (after an error, or for the next packet).
  void retry() => state = const ScanState(step: ScanStep.scanning);

  /// Adds the matched generic name to the list. True on success; the
  /// scanner then returns to the viewfinder for the next packet.
  Future<bool> addMatched() async {
    final ScanResult? result = state.result;
    if (result == null || state.busy) return false;
    state = ScanState(step: ScanStep.matched, result: result, busy: true);
    final bool ok = await ref
        .read(medsProvider.notifier)
        .add(result.genericName);
    state = ok
        ? const ScanState(step: ScanStep.scanning)
        : ScanState(step: ScanStep.matched, result: result);
    return ok;
  }
}

final scanProvider = NotifierProvider<ScanController, ScanState>(
  ScanController.new,
);
