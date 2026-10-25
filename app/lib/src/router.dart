/// Route table, the sign-in/onboarding gate, and the home screen.
///
/// Sprint 1: report upload. Sprint 2: sign-in, onboarding, profile, and the
/// simplified-report history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'auth_screen.dart';
import 'onboarding_screen.dart';
import 'profile_screen.dart';
import 'providers.dart';
import 'simplify_screen.dart';
import 'theme.dart';
import 'upload_screen.dart';

class AppRouter {
  const AppRouter._();

  static const String home = '/';
  static const String signIn = '/sign-in';
  static const String profile = '/profile';
  static const String uploadReport = '/upload-report';
  static const String simplifyReport = '/simplify-report';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case simplifyReport:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SimplifyReportScreen(),
        );
      case uploadReport:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const UploadReportScreen(),
        );
      case signIn:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const AuthScreen(),
        );
      case home:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const ProfileGate(),
        );
      case profile:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const ProfileScreen(),
        );
      default:
        // Unknown routes land on the profile gate rather than skipping it.
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const ProfileGate(),
        );
    }
  }
}

/// Shows sign-in until there is a session, onboarding until the profile is
/// complete, then the home screen.
class ProfileGate extends ConsumerWidget {
  const ProfileGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    if (session == null) return const AuthScreen();
    final profile = ref.watch(profileProvider);
    return profile.when(
      skipLoadingOnReload: true,
      loading: () =>
          const _GateStatus(message: 'Loading your profile', busy: true),
      error: (error, _) => _GateStatus(
        message: error is ApiException
            ? error.message
            : 'Could not load your profile.',
        onRetry: () => ref.invalidate(profileProvider),
        onSignOut: () => ref.read(authGatewayProvider).signOut(),
      ),
      data: (value) => value.onboardingComplete
          ? const _HomeEntry()
          : const OnboardingScreen(),
    );
  }
}

class _HomeEntry extends ConsumerStatefulWidget {
  const _HomeEntry();

  @override
  ConsumerState<_HomeEntry> createState() => _HomeEntryState();
}

class _HomeEntryState extends ConsumerState<_HomeEntry> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(startWithUploadProvider)) return;
      ref.read(startWithUploadProvider.notifier).consume();
      Navigator.of(context).pushNamed(AppRouter.uploadReport);
    });
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}

class _GateStatus extends StatelessWidget {
  const _GateStatus({
    required this.message,
    this.busy = false,
    this.onRetry,
    this.onSignOut,
  });

  final String message;
  final bool busy;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('MedAIx')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
              ] else ...[
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: context.semantic.error,
                ),
                const SizedBox(height: 16),
              ],
              Text(message, textAlign: TextAlign.center),
              if (!busy) ...[
                const SizedBox(height: 8),
                Text(
                  'Your reports are still saved on your account.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
              if (onSignOut != null) ...[
                const SizedBox(height: 4),
                TextButton(onPressed: onSignOut, child: const Text('Sign out')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Home screen: scan a report, open simplified reports, edit the profile, and
/// check the API connection.
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = ref.watch(profileProvider).valueOrNull;
    final name = profile?.name?.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('MedAIx'),
        actions: [
          IconButton(
            tooltip: 'Your profile',
            onPressed: () => Navigator.of(context).pushNamed(AppRouter.profile),
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => ref.read(authGatewayProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
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
                      color: scheme.primaryContainer,
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
                          name == null || name.isEmpty
                              ? 'LAB REPORTS, EXPLAINED'
                              : 'HELLO, ${name.toUpperCase()}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onPrimaryContainer.withValues(
                              alpha: 0.75,
                            ),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your report, in plain language.',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Scan a lab report. MedAIx reads the text, then '
                          'rewrites the medical terms so you can understand '
                          'it. Numbers are never changed.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
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
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Choose a language, take a photo or select a '
                            'file, then review the extracted text.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
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
                  _ActionTile(
                    icon: Icons.auto_awesome_outlined,
                    title: 'Simplified reports',
                    detail:
                        'Your scanned reports, rewritten in plain language.',
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed(AppRouter.simplifyReport),
                  ),
                  const SizedBox(height: 12),
                  _ActionTile(
                    icon: Icons.person_outline,
                    title: 'Your profile',
                    detail: 'Age, measurements, conditions, and medications.',
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRouter.profile),
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
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const _StepRow(
                            number: '1',
                            title: 'Capture your report',
                            detail:
                                'Take a photo or select an image or PDF, in '
                                'English, Urdu, or Roman Urdu.',
                          ),
                          const SizedBox(height: 14),
                          const _StepRow(
                            number: '2',
                            title: 'Check the extracted text',
                            detail: 'Compare the OCR read with your original.',
                          ),
                          const SizedBox(height: 14),
                          const _StepRow(
                            number: '3',
                            title: 'Read it in plain language',
                            detail:
                                'Medical terms are reworded. Values and '
                                'reference ranges stay exactly as printed.',
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

/// A tappable card for a secondary destination.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
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
