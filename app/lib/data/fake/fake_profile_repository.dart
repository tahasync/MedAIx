/// Fake repository implementation isolated by feature responsibility.
library;

import '../../features/profile/data/profile_repository.dart';
import '../../features/reports/data/reports_repository.dart';

/// Synthetic in-memory implementation for tests and local demos.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    this.latency = const Duration(milliseconds: 200),
    PatientProfile? seed,
    DateTime Function()? clock,
  }) : _profile = seed ?? sampleProfile(),
       _now = clock ?? DateTime.now;

  final Duration latency;
  final DateTime Function() _now;
  PatientProfile _profile;

  /// Obviously fictional sample patient.
  static PatientProfile sampleProfile() => PatientProfile(
    id: 1,
    name: 'Sample Patient',
    email: 'sample@example.com',
    dateOfBirth: DateTime(1998, 5, 14),
    age: 28,
    sexAtBirth: 'male',
    consent: const ProfileConsent(
      terms: true,
      healthData: true,
      version: kConsentVersion,
      acceptedAt: null,
    ),
    conditions: 'Diabetes',
    allergies: 'Peanuts',
    takesMedicines: true,
    medications: 'Metformin 500 mg',
    firstGoal: 'reports',
    heightCm: 172,
    weightKg: 68,
    onboardingComplete: true,
  );

  /// Calls to [save], newest last; tests assert on the partial bodies.
  final List<Map<String, dynamic>> savedBodies = <Map<String, dynamic>>[];
  int deleteCalls = 0;

  PatientProfile get current => _profile;

  @override
  Future<PatientProfile> fetch() async {
    await Future<void>.delayed(latency);
    return _profile;
  }

  @override
  Future<PatientProfile> save(ProfileDraft d) async {
    await Future<void>.delayed(latency);
    final String? name = d.name;
    if (name != null && (name.trim().length < 2 || name.trim().length > 60)) {
      throw const RepositoryException(
        'Use a name between 2 and 60 characters.',
        canRetry: false,
      );
    }
    final DateTime? dob = d.dateOfBirth;
    if (dob != null && PatientProfile.ageAt(dob, today: _now()) < 18) {
      throw const RepositoryException(
        'MedAIx is for adults. A parent or guardian can use it for you.',
        canRetry: false,
      );
    }
    savedBodies.add(d.toJson());
    _profile = _profile.apply(d, now: _now());
    return _profile;
  }

  @override
  Future<void> delete() async {
    await Future<void>.delayed(latency);
    deleteCalls++;
    _profile = _profile.cleared();
  }
}
