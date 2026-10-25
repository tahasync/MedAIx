/// Read-side state for the Reports tab: the list and one report's detail.
/// Both read only from [reportsRepositoryProvider]; screens invalidate them
/// to refresh (pull-to-refresh, "Try again", after an upload).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories.dart';
import '../data/report_models.dart';

/// Every report, newest first. Summary fields only.
final reportsListProvider = FutureProvider<List<LabReport>>(
  (ref) => ref.watch(reportsRepositoryProvider).listReports(),
);

/// Full detail for one report (summary, values, texts).
final reportDetailProvider = FutureProvider.autoDispose.family<LabReport, int>(
  (ref, id) => ref.watch(reportsRepositoryProvider).getReport(id),
);

/// The newest report, or null when there are none. Home's "Latest report".
final latestReportProvider = FutureProvider<LabReport?>((ref) async {
  final List<LabReport> all = await ref.watch(reportsListProvider.future);
  return all.isEmpty ? null : all.first;
});
