/// Routing — Week 0 scaffold.
///
/// A single placeholder route stands in for the Home/Reports/Wellness/Meds/
/// Profile shell, which arrives with Sprint 2's navigation work. No named routes
/// are declared for screens that don't exist yet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'providers.dart';
import 'theme.dart';

class AppRouter {
  const AppRouter._();

  static const String home = '/';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const PlaceholderScreen(),
        );
      default:
        // Unknown routes land on the placeholder rather than crashing.
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const PlaceholderScreen(),
        );
    }
  }
}

/// Temporary scaffold screen — replaced by the real Home screen in Sprint 2.
///
/// Doubles as the Week 0 end-to-end check: tapping the button calls the API's
/// real `/health` route, so on-device loading / success / error states are
/// exercised before any feature code lands.
class PlaceholderScreen extends ConsumerStatefulWidget {
  const PlaceholderScreen({super.key});

  @override
  ConsumerState<PlaceholderScreen> createState() => _PlaceholderScreenState();
}

class _PlaceholderScreenState extends ConsumerState<PlaceholderScreen> {
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'MedAIx',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Smarter care. Better lives.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _checking ? null : _checkConnection,
                icon: _checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.favorite_outline),
                label: Text(_checking ? 'Checking connection' : 'Check connection'),
              ),
              if (_healthy != null) ...[
                const SizedBox(height: 24),
                _StatusBanner(
                  healthy: _healthy!,
                  onRetry: _checkConnection,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Pairs colour with an icon and text so status is never colour-only (§3b).
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.healthy,
    required this.onRetry,
  });

  final bool healthy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final semantics = context.semantic;
    final base = healthy ? semantics.success : semantics.error;
    final container = healthy ? semantics.successContainer : semantics.errorContainer;
    final onContainer =
        healthy ? semantics.onSuccessContainer : semantics.onErrorContainer;

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
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}