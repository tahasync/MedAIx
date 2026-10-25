/// Profile state shared by onboarding, Home (greeting), Profile and More.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories.dart';
import '../../auth/providers/auth_providers.dart';
import '../../home/providers/home_providers.dart';
import '../../reports/data/reports_repository.dart';
import '../../wellness/providers/wellness_providers.dart';
import '../data/profile_repository.dart';

/// Signed-in patient's profile. Refetches when the session changes.
final profileProvider = FutureProvider<PatientProfile>((ref) async {
  final session = ref.watch(authControllerProvider);
  if (session == null) {
    throw const RepositoryException('Please sign in to continue.');
  }
  return ref.watch(profileRepositoryProvider).fetch();
});

/// Save / delete, keeping [profileProvider] in sync.
class ProfileEditor extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<PatientProfile?> save(ProfileDraft draft) async {
    state = const AsyncLoading();
    try {
      final PatientProfile saved = await ref
          .read(profileRepositoryProvider)
          .save(draft);
      ref.invalidate(profileProvider);
      state = const AsyncData(null);
      return saved;
    } on RepositoryException catch (error, stack) {
      state = AsyncError(error, stack);
      return null;
    }
  }

  Future<bool> delete() async {
    state = const AsyncLoading();
    try {
      await ref.read(profileRepositoryProvider).delete();
      await ref.read(wellnessRepositoryProvider).clearLocal();
      ref.invalidate(profileProvider);
      ref.invalidate(wellnessProvider);
      ref.invalidate(habitTodayProvider);
      state = const AsyncData(null);
      return true;
    } on RepositoryException catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
    }
  }
}

final profileEditorProvider = NotifierProvider<ProfileEditor, AsyncValue<void>>(
  ProfileEditor.new,
);
