/// Fake repository implementation isolated by feature responsibility.
library;

import '../../features/meds/data/meds_repository.dart';

/// Synthetic in-memory implementation for tests and local demos.
class FakeMedsRepository implements MedsRepository {
  FakeMedsRepository({
    this.latency = const Duration(milliseconds: 250),
    List<String> seed = const <String>[],
  }) {
    for (final name in seed) {
      _items.add(Medicine(id: _nextId++, name: name));
    }
  }

  final Duration latency;
  final List<Medicine> _items = <Medicine>[];
  int _nextId = 1;

  static const List<String> catalogue = <String>[
    'Metformin 500 mg',
    'Ibuprofen 400 mg',
    'Warfarin 5 mg',
    'Paracetamol 500 mg',
    'Amlodipine 5 mg',
    'Atorvastatin 20 mg',
  ];

  @override
  Future<List<Medicine>> list() async {
    await Future<void>.delayed(latency);
    return List<Medicine>.unmodifiable(_items);
  }

  @override
  Future<List<String>> suggestions() async {
    await Future<void>.delayed(latency);
    final Set<String> have = _items.map((m) => m.name).toSet();
    return catalogue.where((n) => !have.contains(n)).toList();
  }

  @override
  Future<Medicine> add(String name) async {
    await Future<void>.delayed(latency);
    final Medicine m = Medicine(id: _nextId++, name: name.trim());
    _items.add(m);
    return m;
  }

  @override
  Future<void> remove(int id) async {
    await Future<void>.delayed(latency);
    _items.removeWhere((m) => m.id == id);
  }

  @override
  Future<List<InteractionWarning>> checkInteractions() async {
    await Future<void>.delayed(latency * 2);
    final Set<String> names = _items
        .map((m) => m.name.toLowerCase().split(' ').first)
        .toSet();
    final List<InteractionWarning> warnings = <InteractionWarning>[];
    if (names.contains('ibuprofen') && names.contains('warfarin')) {
      warnings.add(
        const InteractionWarning(
          title: 'Ibuprofen with warfarin',
          body:
              'Together they raise the risk of serious bleeding. Don’t take '
              'both unless your doctor agrees.',
        ),
      );
    }
    if (names.contains('metformin') && names.contains('ibuprofen')) {
      warnings.add(
        const InteractionWarning(
          title: 'Ibuprofen with metformin',
          body:
              'Long courses of ibuprofen can strain the kidneys, which also '
              'clear metformin. Short use is usually fine; ask if it is more '
              'than a few days.',
        ),
      );
    }
    return warnings;
  }

  @override
  Future<ScanResult> scanPacket() async {
    await Future<void>.delayed(latency * 4);
    return const ScanResult(
      readName: 'Panadol 500 mg',
      genericName: 'Paracetamol 500 mg',
      safeWithCurrent: true,
      note: 'Safe with your current medicines.',
    );
  }
}
