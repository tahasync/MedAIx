/// Simplified-report screen (Sprint 2).
///
/// Lists stored reports and turns a chosen report's raw OCR text into plain
/// language via `/simplify-report`. Every state the UX baseline requires is
/// covered: empty (no reports yet), loading (list fetch and per-row
/// simplify), error (list failure and simplify failure, both with a retry),
/// and success (a dedicated result page that confirms what happened and
/// offers the next action).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'providers.dart';
import 'theme.dart';

/// Run `/simplify-report` for [reportId] and, on success, open the result as
/// its own scrollable page. A failure is left in [simplifyControllerProvider]
/// for the calling screen to render with a retry.
///
/// Shared by this screen and the upload success view so both entry points
/// behave identically.
Future<void> simplifyAndShow(
  BuildContext context,
  WidgetRef ref,
  int reportId,
) async {
  final notifier = ref.read(simplifyControllerProvider.notifier);
  await notifier.submit(reportId);
  if (!context.mounted) return;

  final state = ref.read(simplifyControllerProvider);
  if (state is! SimplifySuccess) return;

  ref.invalidate(reportsProvider);
  notifier.reset();
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SimplifiedReportPage(result: state.result),
    ),
  );
}

class SimplifyReportScreen extends ConsumerWidget {
  const SimplifyReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simplifyState = ref.watch(simplifyControllerProvider);
    final inProgressId = switch (simplifyState) {
      SimplifyInProgress(:final reportId) => reportId,
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simplified reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh report list',
            onPressed: () => ref.invalidate(reportsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ReportList(
                    inProgressId: inProgressId,
                    busy: inProgressId != null,
                    onSimplify: (reportId) =>
                        simplifyAndShow(context, ref, reportId),
                  ),
                ),
                if (simplifyState case SimplifyFailure(
                  :final message,
                  :final canRetry,
                  :final reportId,
                ))
                  _FailureBanner(
                    message: message,
                    onRetry: canRetry
                        ? () => simplifyAndShow(context, ref, reportId)
                        : null,
                    onDismiss: () =>
                        ref.read(simplifyControllerProvider.notifier).reset(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lists stored reports, newest first, each with a simplify or view action.
class _ReportList extends ConsumerWidget {
  const _ReportList({
    required this.inProgressId,
    required this.busy,
    required this.onSimplify,
  });

  /// Report whose simplification is in flight, so its row shows a spinner.
  final int? inProgressId;

  /// True while any simplification is running; other rows are disabled so two
  /// cannot be started at once.
  final bool busy;
  final ValueChanged<int> onSimplify;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReports = ref.watch(reportsProvider);

    return asyncReports.when(
      skipLoadingOnRefresh: true,
      data: (reports) {
        if (reports.isEmpty) return const _EmptyState();
        return RefreshIndicator(
          onRefresh: () => ref.refresh(reportsProvider.future),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: reports.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return const _Intro();
              final report = reports[index - 1];
              return _ReportRow(
                report: report,
                isSimplifying: inProgressId == report.id,
                onTap: busy ? null : () => onSimplify(report.id),
              );
            },
          ),
        );
      },
      loading: () => const _LoadingState(),
      error: (error, _) => _ErrorState(
        message: error is ApiException
            ? error.message
            : 'Could not load your reports.',
        onRetry: () => ref.invalidate(reportsProvider),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Choose a report to rewrite its medical terms in plain language. '
        'Numbers and reference ranges are never changed.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One report row: filename, upload date, confidence, and the action.
class _ReportRow extends StatelessWidget {
  const _ReportRow({
    required this.report,
    required this.isSimplifying,
    required this.onTap,
  });

  final ReportSummary report;
  final bool isSimplifying;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = context.semantic;

    final Widget trailing;
    if (isSimplifying) {
      trailing = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (report.hasSimplified) {
      trailing = OutlinedButton(onPressed: onTap, child: const Text('View'));
    } else {
      trailing = FilledButton.tonal(
        onPressed: onTap,
        child: const Text('Simplify'),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: report.hasSimplified
                      ? semantics.successContainer
                      : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  report.hasSimplified
                      ? Icons.check_circle_outline
                      : Icons.description_outlined,
                  color: report.hasSimplified
                      ? semantics.onSuccessContainer
                      : scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.imagePath.isEmpty
                          ? 'Report #${report.id}'
                          : report.imagePath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_shortDate(report.uploadedAt)} · '
                      'OCR ${report.confidence.toStringAsFixed(0)}%'
                      '${report.hasSimplified ? ' · Simplified' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  String _shortDate(String iso) {
    final date = DateTime.tryParse(iso)?.toLocal();
    if (date == null) return 'Uploaded';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return 'Uploaded ${date.year}-$month-$day';
  }
}

/// Empty state: explains what belongs here and offers the one next action.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.auto_awesome_outlined,
                size: 34,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No reports yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a lab report first. It will appear here, ready to be '
              'rewritten in plain language.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed('/upload-report'),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan a report'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading state: a skeleton the shape of the rows it replaces.
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row() => Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 160,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 110,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                'Loading your reports',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.45, end: 1.0),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOut,
            builder: (context, value, child) =>
                Opacity(opacity: value, child: child),
            child: Column(children: [row(), row(), row()]),
          ),
        ],
      ),
    );
  }
}

/// List failed to load: plain language plus a retry.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantics = context.semantic;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: semantics.error),
            const SizedBox(height: 16),
            Text(
              'Could not load your reports',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your reports are still saved on your account.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A simplify call failed. Shown under the list so the list stays usable.
class _FailureBanner extends StatelessWidget {
  const _FailureBanner({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final semantics = context.semantic;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: semantics.errorContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: semantics.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: semantics.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: semantics.onErrorContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: semantics.onErrorContainer,
                ),
                child: const Text('Dismiss'),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Success state: the plain-language text, with the original one tap away so
/// the reader can check the rewording against what the lab actually printed.
class SimplifiedReportPage extends StatefulWidget {
  const SimplifiedReportPage({super.key, required this.result});

  final SimplifyResult result;

  @override
  State<SimplifiedReportPage> createState() => _SimplifiedReportPageState();
}

enum _ReportView { simplified, original }

class _SimplifiedReportPageState extends State<SimplifiedReportPage> {
  var _view = _ReportView.simplified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = context.semantic;
    final result = widget.result;
    final text = _view == _ReportView.simplified
        ? result.simplifiedText
        : result.originalText;

    return Scaffold(
      appBar: AppBar(title: const Text('Simplified report')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: semantics.success,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Rewritten in plain language',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result.note.isEmpty
                        ? 'Medical terms were reworded. Values are unchanged.'
                        : result.note,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (result.termsSimplified != null ||
                      result.sentenceCount != null) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (result.termsSimplified != null)
                          _StatChip(
                            icon: Icons.auto_awesome_outlined,
                            label:
                                '${result.termsSimplified} term'
                                '${result.termsSimplified == 1 ? '' : 's'} '
                                'reworded',
                          ),
                        if (result.sentenceCount != null)
                          _StatChip(
                            icon: Icons.notes_outlined,
                            label:
                                '${result.sentenceCount} sentence'
                                '${result.sentenceCount == 1 ? '' : 's'}',
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  SegmentedButton<_ReportView>(
                    segments: const [
                      ButtonSegment(
                        value: _ReportView.simplified,
                        label: Text('Plain language'),
                        icon: Icon(Icons.auto_awesome_outlined),
                      ),
                      ButtonSegment(
                        value: _ReportView.original,
                        label: Text('Original text'),
                        icon: Icon(Icons.description_outlined),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (selection) =>
                        setState(() => _view = selection.first),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _view == _ReportView.simplified
                                      ? 'Plain language'
                                      : 'As read from your report',
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copy text',
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: text),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Text copied'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.copy_all_outlined),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            text.isEmpty ? 'No text available.' : text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: semantics.warningContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: semantics.onWarningContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This rewording helps you read the report. It is '
                            'not medical advice. Discuss the results with '
                            'your doctor.',
                            style: TextStyle(
                              color: semantics.onWarningContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // The result page can be reached from the reports list or
                  // straight from the scanner, so both actions rebuild the
                  // stack from home instead of relying on what is beneath.
                  FilledButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          '/simplify-report',
                          (route) => route.isFirst,
                        ),
                    icon: const Icon(Icons.list_alt_outlined),
                    label: const Text('Back to reports'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          '/upload-report',
                          (route) => route.isFirst,
                        ),
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Scan another report'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
