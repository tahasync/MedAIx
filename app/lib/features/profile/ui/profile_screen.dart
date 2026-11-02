/// Settings › Profile: every questionnaire answer in four cards (Account,
/// Health basics, About you, Consent), readable at a glance and editable in
/// place with the same controls as onboarding. Saves are partial — only
/// the fields that changed are sent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/session_errors.dart';
import '../../auth/providers/auth_providers.dart';
import '../../reports/data/reports_repository.dart';
import '../../settings/ui/settings_screen.dart' show showConfirmSheet;
import '../data/profile_repository.dart';
import '../providers/profile_providers.dart';
import 'profile_edit_form.dart';
import 'profile_read_view.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _editing = false;

  Future<void> _deleteHealthData() async {
    final bool confirmed = await showConfirmSheet(
      context,
      title: 'Delete your health data?',
      body:
          'This permanently deletes your health answers, consent, reports, '
          'wellness logs and other health records. Your name and email stay. '
          'This can’t be undone.',
      confirmLabel: 'Delete my health data',
      cancelLabel: 'Keep my data',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final bool ok = await ref.read(profileEditorProvider.notifier).delete();
    if (!mounted) return;
    showToast(
      context,
      ok
          ? 'Your health data was deleted'
          : 'Couldn’t delete your health data. Nothing was changed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PatientProfile> profile = ref.watch(profileProvider);
    final String? sessionEmail = ref.watch(
      authControllerProvider.select((s) => s?.email),
    );

    return AppScaffold(
      body: AppScreen(
        header: const ScreenHeader(
          title: 'Profile',
          subtitle: 'Used to tailor goals and alerts',
          showBack: true,
        ),
        onRefresh: _editing
            ? null
            : () => ref.refresh(profileProvider.future).then((_) {}),
        children: [
          StateSwitcher(
            child: profile.when(
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              loading: () => const ProfileSkeleton(key: ValueKey('loading')),
              error: (error, _) => isSessionExpired(error)
                  ? ErrorState.sessionExpired(
                      key: const ValueKey('session-expired'),
                      onPrimary: () => ref
                          .read(authControllerProvider.notifier)
                          .expireSession(),
                    )
                  : ErrorCard(
                      key: const ValueKey('error'),
                      title: 'Couldn’t load your profile',
                      message: error is RepositoryException
                          ? error.message
                          : 'Could not load your profile.',
                      dataSafety:
                          'Your details are still saved on your account.',
                      onPrimary: () => ref.invalidate(profileProvider),
                    ),
              data: (value) => _editing
                  ? ProfileEditForm(
                      key: const ValueKey('edit'),
                      profile: value,
                      email: value.email ?? sessionEmail,
                      onSaved: () {
                        setState(() => _editing = false);
                        showToast(context, 'Details saved');
                      },
                      onCancel: () => setState(() => _editing = false),
                    )
                  : ProfileReadView(
                      key: const ValueKey('read'),
                      profile: value,
                      email: value.email ?? sessionEmail,
                      onEdit: () => setState(() => _editing = true),
                      onDelete: _deleteHealthData,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
