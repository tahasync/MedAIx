/// Symptom → specialist matching (fake-only for now).
library;

class SpecialistMatch {
  const SpecialistMatch({required this.specialist, required this.why});

  /// e.g. "Endocrinologist".
  final String specialist;

  /// Plain-language "Why:" explanation.
  final String why;
}

abstract class DoctorRepository {
  Future<List<String>> symptoms();

  Future<SpecialistMatch> match(String symptom);
}
