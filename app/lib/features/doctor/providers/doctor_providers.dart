/// Symptom chips and the specialist match for the Find-a-doctor screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories.dart';
import '../data/doctor_repository.dart';

/// Symptoms offered as chips.
final symptomsProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(doctorRepositoryProvider).symptoms(),
);

/// Which specialist fits [symptom], and why.
final specialistMatchProvider = FutureProvider.autoDispose
    .family<SpecialistMatch, String>(
      (ref, symptom) => ref.watch(doctorRepositoryProvider).match(symptom),
    );
