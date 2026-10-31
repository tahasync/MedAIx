/// Upload a report (mockup `upload` + `uerr`): empty → reading → success
/// (toast, then the report) or error (plain language + recovery).
///
/// Camera access is explained on a card before it is requested; a denial
/// keeps the file fallback one tap away.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../data/report_models.dart';
import '../providers/reports_providers.dart';
import '../providers/upload_providers.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  ReportLanguage _language = ReportLanguage.english;

  /// Showing the camera-permission card instead of the picker.
  bool _askingCamera = false;
  bool _requesting = false;
  bool _cameraGranted = false;
  CameraPermission? _denial;

  Future<void> _submit(String path) => ref
      .read(uploadControllerProvider.notifier)
      .submit(path, language: _language);

  Future<void> _pick(UploadSource source) async {
    final String? path = await ref.read(filePickerProvider)(source);
    if (!mounted) return;
    if (path == null) {
      if (source == UploadSource.camera) {
        showToast(context, 'Couldn’t open the camera. Choose a file instead.');
      }
      return;
    }
    await _submit(path);
  }

  Future<void> _scan() async {
    if (_cameraGranted) return _pick(UploadSource.camera);
    setState(() => _askingCamera = true);
  }

  Future<void> _allowCamera() async {
    if (_denial?.permanentlyDenied == true) {
      await openCameraSettings();
      return;
    }
    setState(() => _requesting = true);
    final CameraPermission result = await ref.read(cameraPermissionProvider)();
    if (!mounted) return;
    if (result.granted) {
      setState(() {
        _cameraGranted = true;
        _askingCamera = false;
        _requesting = false;
        _denial = null;
      });
      await _pick(UploadSource.camera);
    } else {
      setState(() {
        _requesting = false;
        _denial = result;
      });
    }
  }

  void _chooseFileInstead() {
    setState(() => _askingCamera = false);
    _pick(UploadSource.gallery);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UploadState>(uploadControllerProvider, (_, next) {
      if (next is! UploadSuccess) return;
      final String message = next.toastMessage;
      final int id = next.report.id;
      ref.read(uploadControllerProvider.notifier).reset();
      showToast(context, message);
      context.go(AppRoutes.report(id));
    });

    final UploadState state = ref.watch(uploadControllerProvider);
    final bool hasReports =
        (ref.watch(reportsListProvider).valueOrNull?.isNotEmpty ?? false) ||
        (state is UploadIdle && state.hasUploadedBefore);

    const ScreenHeader uploadHeader = ScreenHeader(title: 'Upload report');

    final (Widget header, Widget body) = switch (state) {
      UploadInProgress(:final phase, :final fileName) => (
        ScreenHeader(title: phase.title, subtitle: phase.label),
        _ReadingView(
          key: const ValueKey<String>('reading'),
          phase: phase,
          fileName: fileName,
        ),
      ),
      UploadFailure(:final message, :final canRetry) => (
        uploadHeader,
        ErrorCard(
          key: const ValueKey<String>('failure'),
          title: 'Couldn’t read this photo',
          message: message,
          dataSafety:
              'Retrying this upload uses the same request id, so it will not '
              'create a duplicate report. Your other reports are safe.',
          onPrimary: canRetry
              ? () => ref.read(uploadControllerProvider.notifier).retry()
              : null,
          secondaryLabel: 'Choose another file',
          onSecondary: () =>
              ref.read(uploadControllerProvider.notifier).reset(),
        ),
      ),
      UploadIdle() || UploadSuccess() => (
        uploadHeader,
        _askingCamera
            ? _CameraPermissionCard(
                key: const ValueKey<String>('permission'),
                denial: _denial,
                requesting: _requesting,
                onAllow: _allowCamera,
                onChooseFile: _chooseFileInstead,
              )
            : _PickView(
                key: const ValueKey<String>('pick'),
                hasReports: hasReports,
                language: _language,
                onLanguage: (l) => setState(() => _language = l),
                onScan: _scan,
                onChoose: () => _pick(UploadSource.gallery),
              ),
      ),
    };

    return AppScaffold(
      body: AppScreen(
        header: header,
        children: [StateSwitcher(child: body)],
      ),
    );
  }
}

/// Empty state (mockup `upload`): language chips, the empty card with both
/// actions, and the offline note.
class _PickView extends StatelessWidget {
  const _PickView({
    super.key,
    required this.hasReports,
    required this.language,
    required this.onLanguage,
    required this.onScan,
    required this.onChoose,
  });

  final bool hasReports;
  final ReportLanguage language;
  final ValueChanged<ReportLanguage> onLanguage;
  final VoidCallback onScan;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Report language',
            style: text.bodySmall?.copyWith(color: c.muted),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.chipGap,
          runSpacing: AppSpace.chipGap,
          children: [
            for (final ReportLanguage l in ReportLanguage.values)
              AppChip(
                label: l.label,
                selected: l == language,
                onTap: () => onLanguage(l),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.cardGap),
        EmptyState(
          icon: LucideIcons.fileText,
          title: hasReports ? 'Add a report' : 'No reports yet',
          reason:
              'Add a lab report and we’ll explain every value in plain '
              'language.',
          action: PrimaryButton(
            label: 'Scan a report',
            icon: LucideIcons.camera,
            onPressed: onScan,
          ),
          secondaryAction: GhostButton(
            label: 'Choose from gallery or files',
            icon: LucideIcons.upload,
            onPressed: onChoose,
          ),
        ),
        const SizedBox(height: AppSpace.cardGap),
        Text(
          'Works offline. Reports sync when you reconnect.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: c.muted),
        ),
      ],
    );
  }
}

/// Reading state: progress card, then a skeleton shaped like the Report
/// screen (summary card + three value rows).
class _ReadingView extends StatelessWidget {
  const _ReadingView({super.key, required this.phase, required this.fileName});

  final UploadPhase phase;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconTile(icon: LucideIcons.fileText),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Semantics(
                label: phase.label,
                liveRegion: true,
                child: LinearProgressIndicator(
                  minHeight: AppSize.progressBar,
                  backgroundColor: context.colors.surface2,
                  color: context.colors.primary,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'This can take a little while. Your report stays saved if '
                'the explanation needs a retry.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.colors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.cardGap),
        const SkeletonCard(height: 136),
        const SizedBox(height: AppSpace.gridGap),
        const SkeletonBox(height: 60),
        const SizedBox(height: AppSpace.gridGap),
        const SkeletonBox(height: 60),
      ],
    );
  }
}

/// Mockup `scan` permission card: explain, then ask; a denial keeps the
/// file fallback.
class _CameraPermissionCard extends StatelessWidget {
  const _CameraPermissionCard({
    super.key,
    required this.denial,
    required this.requesting,
    required this.onAllow,
    required this.onChooseFile,
  });

  final CameraPermission? denial;
  final bool requesting;
  final VoidCallback onAllow;
  final VoidCallback onChooseFile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool permanent = denial?.permanentlyDenied == true;
    final String body = denial == null
        ? 'We use the camera only to photograph your report so we can read '
              'the values. MedAIx doesn’t keep the photo on your phone.'
        : permanent
        ? 'Camera access is turned off for MedAIx. Turn it on in Settings, '
              'or choose a photo or PDF you already have.'
        : 'Camera access was declined. You can allow it now, or choose a '
              'photo or PDF you already have.';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconTile(icon: LucideIcons.camera),
          ),
          const SizedBox(height: AppSpace.md + 2),
          Text('Camera access needed', style: text.titleLarge),
          const SizedBox(height: AppSpace.sm),
          Text(body, style: text.bodyMedium?.copyWith(color: c.muted)),
          const SizedBox(height: AppSpace.lg),
          PrimaryButton(
            label: permanent ? 'Open settings' : 'Allow camera',
            loading: requesting,
            onPressed: onAllow,
          ),
          const SizedBox(height: AppSpace.lg),
          GhostButton(
            label: 'Choose a file instead',
            icon: LucideIcons.upload,
            onPressed: requesting ? null : onChooseFile,
          ),
        ],
      ),
    );
  }
}
