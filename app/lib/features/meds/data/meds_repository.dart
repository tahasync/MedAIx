/// Medicines, interaction checks and packet scanning. Fake-only until the
/// backend grows these endpoints.
library;

class Medicine {
  const Medicine({required this.id, required this.name});

  final int id;

  /// e.g. "Metformin 500 mg".
  final String name;
}

/// A risky combination, written in plain language.
class InteractionWarning {
  const InteractionWarning({required this.title, required this.body});

  /// e.g. "Ibuprofen with warfarin".
  final String title;

  /// e.g. "Together they raise the risk of serious bleeding…".
  final String body;
}

/// What the scanner read from a packet.
class ScanResult {
  const ScanResult({
    required this.readName,
    required this.genericName,
    required this.safeWithCurrent,
    required this.note,
  });

  /// e.g. "Panadol 500 mg".
  final String readName;

  /// e.g. "Paracetamol 500 mg".
  final String genericName;
  final bool safeWithCurrent;

  /// e.g. "Safe with your current medicines."
  final String note;
}

abstract class MedsRepository {
  Future<List<Medicine>> list();

  /// Names offered when adding (the picker). Fake data for now.
  Future<List<String>> suggestions();

  Future<Medicine> add(String name);

  Future<void> remove(int id);

  Future<List<InteractionWarning>> checkInteractions();

  /// Simulates reading the packet in the viewfinder.
  Future<ScanResult> scanPacket();
}
