/// Route table for the current home screen and Sprint 1 report upload flow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'providers.dart';
import 'theme.dart';
import 'upload_screen.dart';

class AppRouter {
  const AppRouter._();

  static const String home = '/';
  static const String uploadReport = '/upload-report';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case uploadReport:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const UploadReportScreen(),
        );
      case home:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const HomeScreen(),
        );
      default:
        // Unknown routes land on the placeholder rather than crashing.
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const HomeScreen(),
        );
    }
  }
}

/// Sprint 1 home screen with a report-scanning entry point and API health check.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _checking = false;
  bool? _healthy;

  Future<void> _checkConnection() async {
    setState(() {
      _checking = true;
      _healthy = null;
    });

    bool healthy;
    try {
      healthy = await ref.read(apiClientProvider).checkHealth();
    } on ApiException {
      healthy = false;
    }

    if (!mounted) return;
    setState(() {
      _checking = false;
      _healthy = healthy;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('MedAIx')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.document_scanner_outlined,
                            size: 30,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'LAB REPORT OCR',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer
                                    .withValues(alpha: 0.75),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your report, in readable text.',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Capture a report or choose a file. MedAIx extracts '
                          'the text so you can review it against the original.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            _LanguagePill(label: 'English'),
                            _LanguagePill(label: 'Urdu'),
                            _LanguagePill(label: 'Roman Urdu'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Start a scan',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Choose a language, take a photo or select a file, '
                            'then review the extracted text.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => Navigator.of(
                                context,
                              ).pushNamed(AppRouter.uploadReport),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Scan a report'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Three simple steps',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 16),
                          const _StepRow(
                            number: '1',
                            title: 'Choose a report',
                            detail: 'Take a photo or select an image or PDF.',
                          ),
                          const SizedBox(height: 14),
                          const _StepRow(
                            number: '2',
                            title: 'Select its language',
                            detail: 'English, Urdu, or Roman Urdu.',
                          ),
                          const SizedBox(height: 14),
                          const _StepRow(
                            number: '3',
                            title: 'Review the extracted text',
                            detail: 'Check OCR output against your original.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _checking ? null : _checkConnection,
                    icon: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_outlined),
                    label: Text(
                      _checking
                          ? 'Checking connection'
                          : 'Check service connection',
                    ),
                  ),
                  if (_healthy != null) ...[
                    const SizedBox(height: 8),
                    _StatusBanner(
                      healthy: _healthy!,
                      onRetry: _checkConnection,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colors.onPrimaryContainer.withValues(alpha: 0.16),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pairs colour with an icon and text so status is never colour-only, per the
/// Color System's semantic-state rule.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.healthy, required this.onRetry});

  final bool healthy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final semantics = context.semantic;
    final base = healthy ? semantics.success : semantics.error;
    final container = healthy
        ? semantics.successContainer
        : semantics.errorContainer;
    final onContainer = healthy
        ? semantics.onSuccessContainer
        : semantics.onErrorContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: base.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                healthy ? Icons.check_circle_outline : Icons.error_outline,
                color: base,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  healthy
                      ? 'Connected to the MedAIx service.'
                      : 'Could not reach the MedAIx service.',
                  style: TextStyle(color: onContainer),
                ),
              ),
            ],
          ),
          if (!healthy) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}
