/// Reports tab (mockup `reports`): one card listing every report, then the
/// upload button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/api/api_client.dart';
import '../../../theme/app_theme.dart';
import '../../auth/data/session_errors.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/report_models.dart';
import '../data/reports_repository.dart';
import '../providers/reports_providers.dart';

/// Widest a status label may grow before it ellipsises.
const double _statusMaxWidth = 150;

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final TextEditingController _searchController = TextEditingController();
  _ReportsFilter _filter = _ReportsFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(reportsListProvider);
    try {
      await ref.read(reportsListProvider.future);
    } on RepositoryException {
      // The error state renders itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    final WidgetRef ref = this.ref;
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
              loading: () => SlowOperationHint(
                pending: true,
                onRetry: () => ref.invalidate(reportsListProvider),
                child: const _ReportsSkeleton(
                  key: ValueKey<String>('reports-loading'),
                ),
              ),
              error: (error, _) => isSessionExpired(error)
                  ? ErrorState.sessionExpired(
                      key: const ValueKey<String>('session-expired'),
                      onPrimary: () => ref
                          .read(authControllerProvider.notifier)
                          .expireSession(),
                    )
                  : error is RepositoryException &&
                        error.cause is ApiException &&
                        (error.cause! as ApiException).statusCode != null &&
                        (error.cause! as ApiException).statusCode! >= 500
                  ? ErrorState.serverError(
                      key: const ValueKey<String>('reports-server-error'),
                      onPrimary: () => ref.invalidate(reportsListProvider),
                      onSecondary: () => showSupportSheet(context),
                    )
                  : ErrorCard(
                      key: const ValueKey<String>('reports-error'),
                      title: 'Couldn’t load your reports',
                      message: error is RepositoryException
                          ? error.message
                          : 'Could not reach the MedAIx service.',
                      dataSafety:
                          'Your reports are still saved on your account.',
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
                        label: 'Add a report',
                        icon: LucideIcons.upload,
                        onPressed: () => context.go(AppRoutes.upload),
                      ),
                    )
                  : _reportContent(context, list),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportContent(BuildContext context, List<LabReport> reports) {
    final String query = _searchController.text.trim().toLowerCase();
    final List<LabReport> visible = reports.where((report) {
      final bool matchesQuery =
          query.isEmpty ||
          <String>[
            report.title,
            report.statusText,
            ...report.values.map((value) => value.name),
          ].any((text) => text.toLowerCase().contains(query));
      if (!matchesQuery) return false;
      return switch (_filter) {
        _ReportsFilter.all => true,
        _ReportsFilter.needsAttention =>
          report.attentionCount > 0 ||
              report.status == ValueStatus.warn ||
              report.status == ValueStatus.error,
        _ReportsFilter.last30Days => _isRecent(report.date),
      };
    }).toList();

    return Column(
      key: const ValueKey<String>('reports'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey<String>('reports-search'),
          controller: _searchController,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search reports',
            prefixIcon: const Icon(LucideIcons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(LucideIcons.x),
                  ),
            filled: true,
            fillColor: context.colors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            _filterChip(_ReportsFilter.all, 'All'),
            _filterChip(_ReportsFilter.needsAttention, 'Needs attention'),
            _filterChip(_ReportsFilter.last30Days, 'Last 30 days'),
          ],
        ),
        const SizedBox(height: AppSpace.cardGap),
        if (visible.isEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No matching reports',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'Try another search or clear your filters.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: context.colors.muted),
                ),
                const SizedBox(height: AppSpace.md),
                PrimaryButton(
                  label: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _filter = _ReportsFilter.all);
                  },
                ),
              ],
            ),
          )
        else ...[
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.card,
              vertical: AppSpace.sm,
            ),
            child: ListRows(
              rows: [
                for (final LabReport r in visible)
                  ListRow(
                    key: ValueKey<int>(r.id),
                    leading: const IconTile(icon: LucideIcons.fileText),
                    title: r.title,
                    titleBold: true,
                    subtitle: r.dateLabel,
                    // Bounded so the label ellipsises at 320 dp / 200 %
                    // instead of overflowing.
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _statusMaxWidth,
                      ),
                      child: StatusLabel(status: r.status, text: r.statusText),
                    ),
                    semanticLabel:
                        '${r.title}, ${r.dateLabel}, ${r.statusText}',
                    onTap: () => context.go(AppRoutes.report(r.id)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.cardGap),
          PrimaryButton(
            label: 'Add a report',
            icon: LucideIcons.upload,
            onPressed: () => context.go(AppRoutes.upload),
          ),
        ],
      ],
    );
  }

  Widget _filterChip(_ReportsFilter filter, String label) => AppChip(
    label: label,
    selected: _filter == filter,
    onTap: () => setState(() => _filter = filter),
  );

  bool _isRecent(DateTime? date) {
    if (date == null) return false;
    final DateTime now = DateTime.now();
    final DateTime cutoff = now.subtract(const Duration(days: 30));
    return !date.isBefore(cutoff) && !date.isAfter(now);
  }
}

enum _ReportsFilter { all, needsAttention, last30Days }

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
