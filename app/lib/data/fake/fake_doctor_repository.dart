/// Fake repository implementation isolated by feature responsibility.
library;

import '../../features/doctor/data/doctor_repository.dart';

/// Synthetic in-memory implementation for tests and local demos.
class FakeDoctorRepository implements DoctorRepository {
  FakeDoctorRepository({this.latency = const Duration(milliseconds: 200)});

  final Duration latency;

  static const Map<String, SpecialistMatch> _matches =
      <String, SpecialistMatch>{
        'Thirst and tiredness': SpecialistMatch(
          specialist: 'Endocrinologist',
          why:
              'Your HbA1c is rising and you mentioned thirst and tiredness. '
              'These often point to blood sugar changes.',
        ),
        'Chest pain': SpecialistMatch(
          specialist: 'Cardiologist',
          why:
              'Chest pain should be checked by a heart specialist first, '
              'even when it turns out to be muscular. If it is severe or '
              'sudden, go to emergency now.',
        ),
        'Skin rash': SpecialistMatch(
          specialist: 'Dermatologist',
          why:
              'A skin specialist can tell an allergy from an infection by '
              'looking, and you have a listed allergy.',
        ),
        'Joint pain': SpecialistMatch(
          specialist: 'Rheumatologist',
          why:
              'Pain in several joints, especially in the morning, is usually '
              'assessed by a joint and autoimmune specialist.',
        ),
      };

  @override
  Future<List<String>> symptoms() async {
    await Future<void>.delayed(latency);
    return _matches.keys.toList();
  }

  @override
  Future<SpecialistMatch> match(String symptom) async {
    await Future<void>.delayed(latency);
    return _matches[symptom] ??
        const SpecialistMatch(
          specialist: 'General physician',
          why:
              'A general physician can examine you and refer you to the '
              'right specialist.',
        );
  }
}
