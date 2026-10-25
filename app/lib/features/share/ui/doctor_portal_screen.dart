/// Doctor portal (mockup `docscan`): what the doctor sees after scanning a
/// code — read-only access with a countdown, and the shared records.
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

class DoctorPortalScreen extends ConsumerWidget {
  const DoctorPortalScreen({super.key, this.code});

  /// The scanned code (`?code=` on the route). Empty when opened without
  /// one, which the repository treats as unknown.
  final String? code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String key = code ?? '';
    final AsyncValue<DoctorPortalView> view = ref.watch(
      doctorPortalProvider(key),
    );

    return AppScaffold(
      body: AppScreen(
        header: const ScreenHeader(
          title: 'Doctor portal',
          subtitle: 'Scanned just now',
          showBack: true,
        ),
        onRefresh: () => ref.refresh(doctorPortalProvider(key).future),
        children: view.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const [
            SkeletonCard(height: 132),
            SizedBox(height: AppSpace.cardGap),
            SkeletonCard(height: 172),
          ],
          error: (_, _) => [
            ErrorCard(
              title: 'This code has expired or was revoked',
              message: 'Ask the patient to create a new code and scan again.',
              dataSafety: '',
              primaryLabel: 'Back',
              onPrimary: () => context.popOrGo(AppRoutes.settings),
            ),
          ],
          data: (v) => _content(context, v),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, DoctorPortalView v) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CountdownText(
              expiresAt: v.expiresAt,
              spokenLabel: (left) =>
                  'Read-only access, ${describeRemaining(left)} left',
              builder: (context, countdown) => CardTag(
                icon: LucideIcons.shieldCheck,
                label: 'Read-only access · $countdown left',
                color: c.ok,
              ),
            ),
            Semantics(
              header: true,
              child: Text(v.patientName, style: text.titleLarge),
            ),
            Text(v.summary, style: text.bodySmall?.copyWith(color: c.muted)),
          ],
        ),
      ),
      const SizedBox(height: AppSpace.cardGap),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Shared records',
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            ListRows(
              rows: [
                for (final SharedRecord r in v.records)
                  ListRow(
                    title: r.title,
                    leading: IconTile(
                      icon: switch (r.kind) {
                        SharedRecordKind.report => LucideIcons.fileText,
                        SharedRecordKind.medicines => LucideIcons.pill,
                      },
                    ),
                    onTap: () => context.go(switch (r.kind) {
                      SharedRecordKind.report => AppRoutes.reports,
                      SharedRecordKind.medicines => AppRoutes.meds,
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpace.cardGap),
      Text(
        'This view is logged. The patient can revoke it at any time.',
        style: text.bodySmall?.copyWith(color: c.muted),
      ),
    ];
  }
}
