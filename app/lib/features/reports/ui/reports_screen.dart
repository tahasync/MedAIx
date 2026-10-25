/// Reports tab (mockup `reports`): one card listing every report, then the
/// upload button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../data/report_models.dart';
import '../data/reports_repository.dart';
import '../providers/reports_providers.dart';

/// Widest a status label may grow before it ellipsises.
const double _statusMaxWidth = 150;

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(reportsListProvider);
    try {
      await ref.read(reportsListProvider.future);
    } on RepositoryException {
      // The error state renders itself.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LabReport>> reports = ref.watch(reportsListProvider);
    final int? count = reports.valueOrNull?.length;

    return AppScaffold(
      body: AppScreen(
        onRefresh: () => _refresh(ref),
        header: ScreenHeader(
          title: 'Reports',
          subtitle: count == null
              ? null
              : count == 1
              ? '1 report'
              : '$count reports',
        ),
        children: [
          StateSwitcher(
            child: reports.when(
              skipLoadingOnRefresh: true,
              loading: () => const _ReportsSkeleton(
                key: ValueKey<String>('reports-loading'),
              ),
              error: (error, _) => ErrorCard(
                key: const ValueKey<String>('reports-error'),
                title: 'Couldn’t load your reports',
                message: error is RepositoryException
                    ? error.message
                    : 'Could not reach the MedAIx service.',
                dataSafety: 'Your reports are still saved on your account.',
                onPrimary: () => ref.invalidate(reportsListProvider),
              ),
              data: (list) => list.isEmpty
                  ? EmptyState(
                      key: const ValueKey<String>('reports-empty'),
                      icon: LucideIcons.fileText,
                      title: 'No reports yet',
                      reason:
                          'Add a lab report and we’ll explain every value in '
                          'plain language.',
                      action: PrimaryButton(
                        label: 'Upload report',
                        icon: LucideIcons.upload,
                        onPressed: () => context.go(AppRoutes.upload),
                      ),
                    )
                  : Column(
                      key: const ValueKey<String>('reports'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.card,
                            vertical: AppSpace.sm,
                          ),
                          child: ListRows(
                            rows: [
                              for (final LabReport r in list)
                                ListRow(
                                  key: ValueKey<int>(r.id),
                                  leading: const IconTile(
                                    icon: LucideIcons.fileText,
                                  ),
                                  title: r.title,
                                  titleBold: true,
                                  subtitle: r.dateLabel,
                                  // Bounded so the label ellipsises at
                                  // 320 dp / 200 % instead of overflowing.
                                  trailing: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: _statusMaxWidth,
                                    ),
                                    child: StatusLabel(
                                      status: r.status,
                                      text: r.statusText,
                                    ),
                                  ),
                                  semanticLabel:
                                      '${r.title}, ${r.dateLabel}, '
                                      '${r.statusText}',
                                  onTap: () =>
                                      context.go(AppRoutes.report(r.id)),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpace.cardGap),
                        PrimaryButton(
                          label: 'Upload report',
                          icon: LucideIcons.upload,
                          onPressed: () => context.go(AppRoutes.upload),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three skeleton rows the size of real [ListRow]s, inside the card.
class _ReportsSkeleton extends StatelessWidget {
  const _ReportsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(height: 56),
          SizedBox(height: AppSpace.gridGap),
          SkeletonBox(height: 56),
          SizedBox(height: AppSpace.gridGap),
          SkeletonBox(height: 56),
        ],
      ),
    );
  }
}
