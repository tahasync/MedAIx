/// "More" tab (mockup `settings`): preferences, records, account, help.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/features.dart';
import '../../../core/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../../auth/providers/auth_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../providers/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await showConfirmSheet(
      context,
      title: 'Sign out of MedAIx?',
      body: 'Your reports stay saved on your account.',
      confirmLabel: 'Sign out',
      cancelLabel: 'Stay signed in',
    );
    if (!confirmed) return;
    await ref.read(authGatewayProvider).signOut();
  }

  Future<void> _deleteData(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await showConfirmSheet(
      context,
      // DELETE /profile also removes the reports stored for this account.
      title: 'Delete your health details?',
      body:
          'This removes your profile details and all your reports from '
          'MedAIx. This can’t be undone. Your sign-in stays.',
      confirmLabel: 'Delete my data',
      cancelLabel: 'Keep my data',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final bool ok = await ref.read(profileEditorProvider.notifier).delete();
    if (!context.mounted) return;
    showToast(
      context,
      ok
          ? 'Your details were deleted'
          : 'Couldn’t delete your details. Nothing was changed.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(themeModeProvider);
    final ThemeModeController theme = ref.read(themeModeProvider.notifier);
    final bool followSystem = mode == ThemeMode.system;
    final FeatureFlags features = ref.watch(featuresProvider);
    final bool effectiveDark =
        mode == ThemeMode.dark ||
        (followSystem &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return AppScaffold(
      body: AppScreen(
        header: const ScreenHeader(title: 'Settings'),
        children: [
          const SectionTitle('Preferences', first: true),
          AppCard(
            child: ListRows(
              rows: [
                if (features.reminders)
                  ListRow(
                    title: 'Reminders',
                    onTap: () => context.go(AppRoutes.reminders),
                  ),
                ListRow(
                  title: 'Dark appearance',
                  trailing: AppSwitch(
                    value: effectiveDark,
                    label: 'Dark appearance',
                    onChanged: theme.setDark,
                  ),
                ),
                ListRow(
                  title: 'Follow system theme',
                  trailing: AppSwitch(
                    value: followSystem,
                    label: 'Follow system theme',
                    onChanged: (on) => on
                        ? theme.setMode(ThemeMode.system)
                        : theme.setDark(effectiveDark),
                  ),
                ),
              ],
            ),
          ),
          if (features.share || features.doctorPortal) ...[
            const SectionTitle('Records'),
            AppCard(
              child: ListRows(
                rows: [
                  if (features.share)
                    ListRow(
                      title: 'Share with doctor',
                      onTap: () => context.go(AppRoutes.share),
                    ),
                  if (features.doctorPortal)
                    ListRow(
                      title: 'Doctor portal',
                      onTap: () => context.go(AppRoutes.doctorPortal),
                    ),
                ],
              ),
            ),
          ],
          const SectionTitle('Account'),
          AppCard(
            child: ListRows(
              rows: [
                ListRow(
                  title: 'Profile and health details',
                  onTap: () => context.go(AppRoutes.profile),
                ),
                ListRow(
                  title: 'Export my data',
                  onTap: () => showToast(
                    context,
                    'Export is coming soon. Your data stays on your account.',
                  ),
                ),
                ListRow(title: 'Sign out', onTap: () => _signOut(context, ref)),
                ListRow(
                  title: 'Delete my data',
                  destructive: true,
                  trailing: const SizedBox.shrink(),
                  onTap: () => _deleteData(context, ref),
                ),
              ],
            ),
          ),
          const SectionTitle('Help and support'),
          AppCard(
            child: ListRows(
              rows: [
                ListRow(
                  title: 'Frequently asked questions',
                  onTap: () => showInfoSheet(
                    context,
                    title: 'Frequently asked questions',
                    paragraphs: _faq,
                  ),
                ),
                ListRow(
                  title: 'Troubleshooting',
                  onTap: () => showInfoSheet(
                    context,
                    title: 'Troubleshooting',
                    paragraphs: _troubleshooting,
                  ),
                ),
                ListRow(
                  title: 'Contact support',
                  onTap: () => showInfoSheet(
                    context,
                    title: 'Contact support',
                    paragraphs: _support,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const List<String> _faq = <String>[
  'MedAIx reads your lab reports and explains each value in plain language. '
      'It is not a diagnosis; always confirm anything that worries you with '
      'your doctor.',
  'Your reports and health details are stored on your account and are only '
      'shared when you create a time-limited code for a doctor.',
  'Reminders are delivered on this device only, so turning them on here '
      'does not affect your other devices.',
];

const List<String> _troubleshooting = <String>[
  'If a report could not be read, retake the photo in good light with the '
      'whole page in frame. Nothing is saved until the values are found.',
  'If the app says you are offline, your changes are kept on the device and '
      'sync automatically when the connection returns.',
  'Signing out and back in refreshes your account data. Your reports stay '
      'saved on your account.',
];

const List<String> _support = <String>[
  'Email support@medaix.app with a short description of what happened. '
      'Please don’t include report photos in the email.',
  'We reply within two working days. For anything urgent about your health, '
      'contact your doctor or local emergency services.',
];

/// Bottom sheet with a title, one line of context and a confirm / cancel
/// pair. Returns true when confirmed.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
}) async {
  final bool? result = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (context) => _SheetFrame(
      title: title,
      children: [
        Text(
          body,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.colors.muted),
        ),
        const SizedBox(height: AppSpace.xl),
        if (destructive)
          _DangerButton(
            label: confirmLabel,
            onPressed: () => Navigator.of(context).pop(true),
          )
        else
          PrimaryButton(
            label: confirmLabel,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        const SizedBox(height: AppSpace.xs),
        LinkButton(
          label: cancelLabel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Bottom sheet with a title and a few short paragraphs.
Future<void> showInfoSheet(
  BuildContext context, {
  required String title,
  required List<String> paragraphs,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => _SheetFrame(
      title: title,
      scrollable: true,
      children: [
        for (int i = 0; i < paragraphs.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpace.lg),
          Text(paragraphs[i], style: Theme.of(context).textTheme.bodyMedium),
        ],
        const SizedBox(height: AppSpace.xl),
        GhostButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.children,
    this.scrollable = false,
  });

  final String title;
  final List<Widget> children;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: AppSpace.sm),
        ...children,
      ],
    );
    // The sheet's bottom edge is the screen's, so clear the gesture bar.
    final Widget body = Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screen,
        0,
        AppSpace.screen,
        AppSpace.screen + MediaQuery.paddingOf(context).bottom,
      ),
      child: column,
    );
    if (!scrollable) return body;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: SingleChildScrollView(child: body),
    );
  }
}

/// A [PrimaryButton] filled with the error colour, for the single
/// destructive confirmation in the app. Local because the kit's primary
/// button has no colour parameter.
class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: c.error,
          foregroundColor: c.onPrimary,
          minimumSize: const Size(AppSize.button, AppSize.button),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.buttonAll,
          ),
          textStyle: Theme.of(context).textTheme.labelLarge,
          elevation: 0,
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
