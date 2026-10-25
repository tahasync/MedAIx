/// Share with doctor (mockup `qr`): pick a duration and create a code, or
/// show the active QR with its countdown and "Revoke access now".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../data/share_repository.dart';
import '../providers/share_providers.dart';
import 'countdown.dart';

class ShareScreen extends ConsumerWidget {
  const ShareScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final int minutes = ref.read(shareDurationProvider);
    final ShareSession? session = await ref
        .read(shareProvider.notifier)
        .create(minutes);
    if (session != null && context.mounted) {
      showToast(context, 'Code created for ${session.minutes} minutes');
    }
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final bool ok = await ref.read(shareProvider.notifier).revoke();
    if (ok && context.mounted) showToast(context, 'Access revoked');
  }

  void _expired(BuildContext context, WidgetRef ref) {
    ref.read(shareProvider.notifier).expire();
    if (context.mounted) showToast(context, 'Code expired');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ShareSession?> share = ref.watch(shareProvider);
    final bool busy = share.isLoading;

    return AppScaffold(
      body: AppScreen(
        header: const ScreenHeader(
          title: 'Share with doctor',
          subtitle: 'Time-limited, read-only',
          showBack: true,
        ),
        onRefresh: () => ref.read(shareProvider.notifier).refresh(),
        children: share.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const [
            SkeletonCard(height: 230),
            SizedBox(height: AppSpace.cardGap),
            SkeletonBox(height: AppSize.chipLarge, radius: AppRadius.chip),
            SizedBox(height: AppSpace.cardGap),
            SkeletonBox(height: AppSize.button, radius: AppRadius.button),
          ],
          error: (error, _) => [
            ErrorCard(
              title: 'Couldn’t update sharing',
              message: friendlyShareError(
                error,
                'We couldn’t reach the sharing service.',
              ),
              dataSafety:
                  'Your records are still private and nothing was changed.',
              onPrimary: () => ref.read(shareProvider.notifier).refresh(),
            ),
          ],
          data: (session) => session == null
              ? _empty(context, ref, busy: busy)
              : _active(context, ref, session, busy: busy),
        ),
      ),
    );
  }

  List<Widget> _empty(
    BuildContext context,
    WidgetRef ref, {
    required bool busy,
  }) {
    final int selected = ref.watch(shareDurationProvider);
    return [
      const EmptyState(
        icon: LucideIcons.qrCode,
        title: 'No active codes',
        reason:
            'Create a code your doctor scans to view selected records. '
            'You choose how long it lasts.',
      ),
      const SizedBox(height: AppSpace.cardGap),
      Row(
        children: [
          for (int i = 0; i < kShareDurations.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.chipGap),
            Expanded(
              child: AppChip(
                label: '${kShareDurations[i]} min',
                selected: kShareDurations[i] == selected,
                large: true,
                expand: true,
                onTap: busy
                    ? null
                    : () => ref
                          .read(shareDurationProvider.notifier)
                          .select(kShareDurations[i]),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: AppSpace.cardGap),
      PrimaryButton(
        label: 'Create code',
        loading: busy,
        onPressed: () => _create(context, ref),
      ),
    ];
  }

  List<Widget> _active(
    BuildContext context,
    WidgetRef ref,
    ShareSession session, {
    required bool busy,
  }) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return [
      FadeIn(
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              QrCard(
                seed: session.seed,
                semanticLabel: 'QR code, valid for one doctor visit',
              ),
              const SizedBox(height: AppSpace.cardGap),
              CountdownText(
                expiresAt: session.expiresAt,
                spokenLabel: (left) => 'Expires in ${describeRemaining(left)}',
                onExpired: () => _expired(context, ref),
                builder: (context, countdown) => Text(
                  'Expires in $countdown',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                'Your doctor sees reports and medicines only',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: c.muted),
              ),
              const SizedBox(height: AppSpace.cardGap),
              GhostButton(
                label: 'Revoke access now',
                loading: busy,
                onPressed: () => _revoke(context, ref),
              ),
            ],
          ),
        ),
      ),
      Center(
        child: LinkButton(
          label: 'Open doctor portal preview',
          // Pushed, not replaced, so Back returns to the QR code.
          onPressed: () =>
              context.push('${AppRoutes.doctorPortal}?code=${session.code}'),
        ),
      ),
    ];
  }
}
