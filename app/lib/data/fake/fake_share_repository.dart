/// Fake repository implementation isolated by feature responsibility.
library;

import '../../features/share/data/share_repository.dart';

/// Synthetic in-memory implementation for tests and local demos.
class FakeShareRepository implements ShareRepository {
  FakeShareRepository({
    this.latency = const Duration(milliseconds: 250),
    DateTime Function()? clock,
    this.patientName = 'Muhammad',
  }) : _now = clock ?? DateTime.now;

  final Duration latency;
  final DateTime Function() _now;
  final String patientName;
  ShareSession? _session;
  int _counter = 0;

  @override
  Future<ShareSession?> active() async {
    await Future<void>.delayed(latency);
    final s = _session;
    if (s != null && s.isExpired(_now())) _session = null;
    return _session;
  }

  @override
  Future<ShareSession> create({required int minutes}) async {
    await Future<void>.delayed(latency);
    final DateTime now = _now();
    _counter++;
    _session = ShareSession(
      code: 'MDX-${now.millisecondsSinceEpoch.toRadixString(36)}-$_counter',
      minutes: minutes,
      createdAt: now,
      expiresAt: now.add(Duration(minutes: minutes)),
    );
    return _session!;
  }

  @override
  Future<void> revoke() async {
    await Future<void>.delayed(latency);
    _session = null;
  }

  @override
  Future<DoctorPortalView> portalView(String code) async {
    await Future<void>.delayed(latency);
    final s = _session;
    final DateTime expires = s != null && s.code == code && !s.isExpired(_now())
        ? s.expiresAt
        : _now().add(const Duration(minutes: 28, seconds: 14));
    return DoctorPortalView(
      patientName: patientName,
      summary: 'Diabetes · Peanut allergy',
      records: const <SharedRecord>[
        SharedRecord(
          kind: SharedRecordKind.report,
          title: 'Blood test, 18 Oct',
        ),
        SharedRecord(
          kind: SharedRecordKind.medicines,
          title: 'Current medicines (3)',
        ),
      ],
      expiresAt: expires,
    );
  }
}
