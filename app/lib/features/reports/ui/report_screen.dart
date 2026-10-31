/// One report (mockup `report`): a report-aware plain-language summary,
/// a card per parsed value, and the trend button. The original OCR text is
/// always one toggle away for checking uncertain extraction.
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
import '../providers/trends_providers.dart';

/// Below this OCR confidence the screen warns that numbers may be wrong.
const double kLowConfidence = 60;

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<LabReport> report = ref.watch(
      reportDetailProvider(widget.id),
    );
    final LabReport? value = report.valueOrNull;

    return AppScaffold(
      body: AppScreen(
        header: ScreenHeader(
          title: value?.title ?? 'Report',
          subtitle: value == null
              ? null
              : '${value.dateLabel} · ${value.title}',
          showBack: true,
        ),
        children: [
          StateSwitcher(
            child: report.when(
              skipLoadingOnRefresh: true,
              loading: () =>
                  const _ReportLoading(key: ValueKey<String>('report-loading')),
              error: (error, _) => ErrorCard(
                key: const ValueKey<String>('report-error'),
                title: 'Couldn’t open this report',
                message: error is RepositoryException
                    ? error.message
                    : 'Could not reach the MedAIx service.',
                dataSafety: 'Your reports are still saved on your account.',
                onPrimary: error is RepositoryException && !error.canRetry
                    ? null
                    : () => ref.invalidate(reportDetailProvider(widget.id)),
                secondaryLabel: 'Back to reports',
                onSecondary: () => context.popOrGo(AppRoutes.reports),
              ),
              data: (r) => _ReportBody(
                key: const ValueKey<String>('report'),
                report: r,
                showOriginal: _showOriginal,
                onToggle: (original) =>
                    setState(() => _showOriginal = original),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportLoading extends StatelessWidget {
  const _ReportLoading({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(height: 16, width: 112),
            SizedBox(height: AppSpace.md),
            SkeletonBox(height: 22, width: 240),
            SizedBox(height: AppSpace.sm),
            SkeletonBox(height: 16, width: 180),
          ],
        ),
      ),
      for (int i = 0; i < 3; i++) ...[
        const SizedBox(height: AppSpace.cardGap),
        const AppCard(
          child: Row(
            children: [
              SkeletonBox(height: 44, width: 44),
              SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 16, width: 120),
                    SizedBox(height: AppSpace.sm),
                    SkeletonBox(height: 20, width: 76),
                  ],
                ),
              ),
              SkeletonBox(height: 24, width: 82),
            ],
          ),
        ),
      ],
    ],
  );
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    super.key,
    required this.report,
    required this.showOriginal,
    required this.onToggle,
  });

  final LabReport report;
  final bool showOriginal;
  final ValueChanged<bool> onToggle;

  /// Marker the trend opens on: the first value needing attention, else
  /// the first value, else HbA1c.
  String get _trendMarker {
    for (final ReportValue v in report.values) {
      if (v.status == ValueStatus.warn || v.status == ValueStatus.error) {
        return v.name;
      }
    }
    return report.values.firstOrNull?.name ?? kDefaultTrendMarker;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasOriginal = report.originalText.trim().isNotEmpty;
    final bool lowConfidence =
        report.confidence != null && report.confidence! < kLowConfidence;
    final String plain = report.hasValues
        ? report.summary
        : (report.simplifiedText.trim().isNotEmpty
              ? report.simplifiedText
              : report.summary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lowConfidence) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardTag(
                  icon: LucideIcons.triangleAlert,
                  label: 'This photo was hard to read',
                  color: c.warn,
                ),
                Text(
                  'Some numbers may be wrong. Check them against your paper '
                  'report before acting on them.',
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.cardGap),
        ],
        if (report.parseNote != null) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardTag(
                  icon: LucideIcons.info,
                  label: report.parseNote!,
                  color: c.muted,
                ),
                Text(
                  'The original photo is still available. Check any missing '
                  'numbers against the paper report.',
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.cardGap),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardTag(
                icon: LucideIcons.sparkles,
                label: 'In plain words',
              ),
              Text(
                plain.isEmpty ? 'We couldn’t explain this report yet.' : plain,
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
        if (hasOriginal) ...[
          const SizedBox(height: AppSpace.cardGap),
          Wrap(
            spacing: AppSpace.chipGap,
            runSpacing: AppSpace.chipGap,
            children: [
              AppChip(
                label: 'Plain words',
                selected: !showOriginal,
                onTap: () => onToggle(false),
              ),
              AppChip(
                label: 'Original text',
                selected: showOriginal,
                onTap: () => onToggle(true),
              ),
            ],
          ),
        ],
        StateSwitcher(
          child: showOriginal && hasOriginal
              ? Padding(
                  key: const ValueKey<String>('original'),
                  padding: const EdgeInsets.only(top: AppSpace.cardGap),
                  child: _OriginalCard(text: report.originalText),
                )
              : Column(
                  key: const ValueKey<String>('values'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final ReportValue v in report.values) ...[
                      const SizedBox(height: AppSpace.cardGap),
                      _ValueCard(value: v),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: AppSpace.cardGap),
        PrimaryButton(
          label: 'View trend over time',
          onPressed: () => context.go(
            report.values.isEmpty
                ? AppRoutes.trends
                : '${AppRoutes.trends}?marker=${Uri.encodeQueryComponent(_trendMarker)}',
          ),
        ),
      ],
    );
  }
}

/// Mockup value card: bold name + status, h2 value, muted explanation.
class _ValueCard extends StatelessWidget {
  const _ValueCard({required this.value});

  final ReportValue value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return AppCard(
      semanticLabel:
          '${value.name}, ${value.value}, ${value.statusText}. '
          '${value.explanation}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  value.name,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: AppSpace.lg),
              Flexible(
                child: StatusLabel(
                  status: value.status,
                  text: value.statusText,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(value.value, style: text.titleLarge),
          const SizedBox(height: AppSpace.xs),
          Text(
            value.explanation,
            style: text.bodySmall?.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}

/// The OCR text as read, selectable so it can be copied or checked.
class _OriginalCard extends StatelessWidget {
  const _OriginalCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final TextTheme theme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTag(icon: LucideIcons.fileSearch, label: 'Original text'),
          SelectableText(text, style: theme.bodyMedium),
        ],
      ),
    );
  }
}
