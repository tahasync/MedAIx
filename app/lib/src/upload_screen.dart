/// Report upload screen (Sprint 1), with the Sprint 2 hand-off.
///
/// Implements empty, loading, error, and success states, with camera and file
/// entry points feeding the same language-aware OCR request.
///
/// Success shows the raw read so OCR accuracy stays measurable on its own,
/// then offers "Simplify this report" as the next step, which runs the
/// Sprint 2 `/simplify-report` call and opens the plain-language view.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';
import 'providers.dart';
import 'simplify_screen.dart';
import 'theme.dart';

class UploadReportScreen extends ConsumerStatefulWidget {
  const UploadReportScreen({
    super.key,
    this.onPickFile,
    this.onTakePhoto,
    this.onRequestCameraPermission,
  });

  /// Injected in tests so widget tests do not need a platform channel.
  final Future<String?> Function()? onPickFile;

  /// Injected in tests so camera and permission platform channels are avoided.
  final Future<String?> Function()? onTakePhoto;
  final Future<bool> Function()? onRequestCameraPermission;

  @override
  ConsumerState<UploadReportScreen> createState() => _UploadReportScreenState();
}

class _UploadReportScreenState extends ConsumerState<UploadReportScreen> {
  ReportOcrLanguage _language = ReportOcrLanguage.english;

  Future<String?> _pickFile() async {
    if (widget.onPickFile != null) return widget.onPickFile!();

    try {
      // file_picker 13 exposes static methods that return the list directly,
      // with no `platform` instance. Single-select, so the first entry is the
      // pick and an empty list means the user cancelled.
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      );
      return files.isEmpty ? null : files.first.path;
    } on PlatformException {
      // No file manager available, or the picker was dismissed.
      return null;
    }
  }

  Future<String?> _takePhoto() async {
    if (widget.onTakePhoto != null) return widget.onTakePhoto!();
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 2500,
      );
      return photo?.path;
    } on PlatformException {
      if (!mounted) return null;
      final chooseFile = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Camera unavailable'),
          content: const Text(
            'MedAIx could not open the camera. You can choose an existing photo or PDF instead.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Choose file'),
            ),
          ],
        ),
      );
      if (chooseFile == true && mounted) {
        final path = await _pickFile();
        if (path != null && mounted) await _submitPath(path);
      }
      return null;
    }
  }

  Future<void> _submitPath(String path) async {
    await ref
        .read(uploadControllerProvider.notifier)
        .submit(path, language: _language);
  }

  Future<void> _capturePhoto() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera access'),
        content: const Text(
          'MedAIx uses the camera when you choose Take photo. The photo is '
          'sent to the service to extract its text. You can choose a file instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    Map<String, dynamic>? cameraPermission;
    if (widget.onRequestCameraPermission != null) {
      cameraPermission = {
        'granted': await widget.onRequestCameraPermission!(),
        'permanentlyDenied': false,
      };
    } else if (Theme.of(context).platform == TargetPlatform.android) {
      try {
        cameraPermission = await const MethodChannel(
          'com.tahasync.medaix/camera_permission',
        ).invokeMapMethod<String, dynamic>('requestCameraPermission');
      } on PlatformException {
        cameraPermission = null;
      } on MissingPluginException {
        cameraPermission = null;
      }
    } else {
      // image_picker triggers the native permission prompt on iOS.
      cameraPermission = const {'granted': true, 'permanentlyDenied': false};
    }
    if (!mounted) return;
    if (cameraPermission?['granted'] != true) {
      final permanentlyDenied = cameraPermission?['permanentlyDenied'] == true;
      if (!mounted) return;
      final chooseFile = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Camera access not granted'),
          content: Text(
            permanentlyDenied
                ? 'Allow camera access in Settings to take a report photo, or choose a file instead.'
                : 'You can allow camera access next time, or choose a file instead.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Not now'),
            ),
            if (permanentlyDenied)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  const MethodChannel(
                    'com.tahasync.medaix/camera_permission',
                  ).invokeMethod<void>('openAppSettings');
                },
                child: const Text('Open settings'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Choose file'),
            ),
          ],
        ),
      );
      if (chooseFile == true && mounted) {
        final path = await _pickFile();
        if (path != null && mounted) await _submitPath(path);
      }
      return;
    }

    final path = await _takePhoto();
    if (path != null && mounted) await _submitPath(path);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(uploadControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Report scanner')),
      body: SafeArea(
        child: switch (state) {
          UploadInProgress(:final fileName) => _LoadingView(fileName: fileName),
          UploadSuccess(:final result) => _SuccessView(result: result),
          UploadFailure(:final message, :final canRetry) => _ErrorView(
            message: message,
            canRetry: canRetry,
          ),
          UploadIdle(:final hasUploadBefore) => _EmptyView(
            isRetry: hasUploadBefore,
            language: _language,
            onLanguageChanged: (language) =>
                setState(() => _language = language),
            onTakePhoto: _capturePhoto,
            onPick: () async {
              final path = await _pickFile();
              if (path != null && context.mounted) {
                await _submitPath(path);
              }
            },
          ),
        },
      ),
    );
  }
}

/// Empty state — explains what belongs here and offers the one next action.
class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.onPick,
    required this.onTakePhoto,
    required this.language,
    required this.onLanguageChanged,
    this.isRetry = false,
  });

  final VoidCallback onPick;
  final VoidCallback onTakePhoto;
  final ReportOcrLanguage language;
  final ValueChanged<ReportOcrLanguage> onLanguageChanged;
  final bool isRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.secondaryContainer,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.55,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.document_scanner_outlined,
                        size: 30,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'REPORT OCR',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.78),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            isRetry ? 'Try another image' : 'Scan a lab report',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isRetry
                                ? 'Choose a clearer photo or PDF to retry.'
                                : 'Take a photo or select a report to extract its text.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(
                    Icons.translate_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Report language',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<ReportOcrLanguage>(
                initialValue: language,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                items: ReportOcrLanguage.values
                    .map(
                      (option) => DropdownMenuItem(
                        value: option,
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onLanguageChanged(value);
                },
              ),
              const SizedBox(height: 8),
              Text(
                language.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onTakePhoto,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take photo'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.upload_file),
                label: const Text('Choose report file'),
              ),
              const SizedBox(height: 12),
              Text(
                'JPEG, PNG, or PDF · up to 12 MB',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading state — a skeleton the size of the result it replaces, so the
/// layout does not jump when the read completes.
class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = (MediaQuery.sizeOf(context).width - 48)
        .clamp(0.0, 520.0)
        .toDouble();

    Widget bar(double widthFactor) => Container(
      height: 16,
      width: width * widthFactor,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reading your report',
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // A pulse rather than a shimmer: the shimmer needs a package this app
              // does not take a dependency for on its own account.
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.45, end: 1.0),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOut,
                builder: (context, value, _) => Opacity(
                  opacity: value,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [bar(0.9), bar(0.75), bar(0.6), bar(0.8)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error state — plain language, a recovery action, and reassurance that the
/// file is not lost. Never shows a status code or an exception.
class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.message, required this.canRetry});

  final String message;
  final bool canRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantics = theme.extension<AppSemanticColors>()!;
    final controller = ref.read(uploadControllerProvider.notifier);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: semantics.error),
              const SizedBox(height: 24),
              Text(
                "We couldn't read that report",
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your file has not been lost — try a different photo or file.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (canRetry)
                FilledButton.icon(
                  onPressed: controller.reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                )
              else
                OutlinedButton.icon(
                  onPressed: controller.reset,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Choose a different file'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Success state — confirms what happened and makes the next step obvious.
class _SuccessView extends ConsumerWidget {
  const _SuccessView({required this.result});

  final OcrUploadResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantics = theme.extension<AppSemanticColors>()!;
    final simplifyState = ref.watch(simplifyControllerProvider);
    final simplifying = simplifyState is SimplifyInProgress;
    final simplifyFailure = switch (simplifyState) {
      SimplifyFailure(reportId: final id) && final failure
          when id == result.id =>
        failure,
      _ => null,
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: semantics.success, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Report processed',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Text extracted and saved to your reports. Check it against '
                'the original, then rewrite it in plain language.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (result.isLowConfidence) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: semantics.warningContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: semantics.onWarningContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Some values were hard to read. A clearer photo may give '
                          'a more accurate result.',
                          style: TextStyle(color: semantics.onWarningContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
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
                              'Extracted text',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy extracted text',
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: result.text),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Extracted text copied'),
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
                      // A full-page lab report yields a long transcript. Cap
                      // the card so "Simplify this report" stays on screen;
                      // the text scrolls inside the card.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (MediaQuery.sizeOf(context).height * 0.38)
                              .clamp(160.0, 420.0),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            result.text,
                            style: theme.textTheme.bodyMedium,
                            textDirection: result.language == 'urdu'
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                          ),
                        ),
                      ),
                      const Divider(height: 32),
                      Row(
                        children: [
                          Icon(
                            Icons.speed,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'OCR confidence ${result.confidence.toStringAsFixed(0)}%',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: (result.confidence / 100).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (simplifyFailure != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: semantics.errorContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: semantics.error.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: semantics.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          simplifyFailure.message,
                          style: TextStyle(color: semantics.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: simplifying
                    ? null
                    : () => simplifyAndShow(context, ref, result.id),
                icon: simplifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(
                  simplifying
                      ? 'Simplifying'
                      : simplifyFailure != null
                      ? 'Try again'
                      : 'Simplify this report',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: simplifying
                    ? null
                    : () {
                        ref.read(simplifyControllerProvider.notifier).reset();
                        ref.read(uploadControllerProvider.notifier).reset();
                      },
                icon: const Icon(Icons.add),
                label: const Text('Upload another'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
