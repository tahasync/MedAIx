/// Brand marks rendered in-app: the MedAIx lockup (cross + wordmark) and
/// the cold-start splash. All bitmaps come from `brand/` via
/// `tool/generate_icons.py`; they are flat (no gradient, glow or shadow).
///
/// The launcher icon is the cross on Navy. Android 12+ shows that icon as
/// the system splash; this file is what then shows the lockup.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/providers/settings_providers.dart';
import '../../theme/app_theme.dart';

/// Asset paths registered in `pubspec.yaml`.
class BrandAssets {
  const BrandAssets._();

  /// Lockup on a transparent plate, navy mark + navy/steel wordmark.
  static const String lockup = 'assets/logo.png';

  /// Lockup for dark backgrounds (mauve mark + paper wordmark).
  static const String lockupDark = 'assets/logo-dark.png';

  /// Cross on transparency, navy + steel spark.
  static const String mark = 'assets/mark.png';

  /// Cross on transparency, paper + mauve spark.
  static const String markDark = 'assets/mark-dark.png';
}

/// Full lockup. Picks the light or dark PNG from the current brightness;
/// the PNG is already transparent, so there is no extra plate.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.width = 220});

  final double width;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      image: true,
      label: 'MedAIx',
      child: Image.asset(
        dark ? BrandAssets.lockupDark : BrandAssets.lockup,
        width: width,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// The cross alone, for compact placements.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark ? BrandAssets.markDark : BrandAssets.mark,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
  }
}

/// Full-screen splash: the lockup fades in on Paper or Ink.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: AppMotion.of(
                  context,
                  const Duration(milliseconds: 400),
                ),
                curve: AppMotion.curve,
                builder: (context, t, child) =>
                    Opacity(opacity: t, child: child),
                child: const BrandLockup(width: 220),
              ),
              const SizedBox(height: AppSpace.huge),
              SizedBox(
                width: 140,
                child: ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: AppRadius.barAll,
                    child: LinearProgressIndicator(
                      minHeight: AppSize.progressBar,
                      color: c.primary,
                      backgroundColor: c.surface2,
                    ),
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

/// Shown while Supabase restores the saved account session on startup.
class AccountLoadingScreen extends StatelessWidget {
  const AccountLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.screen),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: AppRadius.cardAll,
                    ),
                    alignment: Alignment.center,
                    child: const BrandMark(size: 68),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  const SizedBox(
                    width: 54,
                    height: 54,
                    child: CircularProgressIndicator(strokeWidth: 4),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  Text(
                    'Setting up your account',
                    textAlign: TextAlign.center,
                    style: text.titleLarge,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Fetching your profile and reports. This can take a '
                    'moment on a slow connection.',
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(color: c.muted),
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

/// Shows [SplashScreen] for at least [minimumDuration] on cold start, then
/// cross-fades to [child].
class BootSplash extends ConsumerStatefulWidget {
  const BootSplash({
    super.key,
    required this.child,
    this.minimumDuration = const Duration(milliseconds: 1400),
  });

  final Widget child;
  final Duration minimumDuration;

  @override
  ConsumerState<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends ConsumerState<BootSplash> {
  Timer? _timer;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.minimumDuration, () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _ready
          ? widget.child
          : MaterialApp(
              key: const ValueKey<String>('boot-splash'),
              title: 'MedAIx',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: ref.watch(themeModeProvider),
              home: const SplashScreen(),
            ),
    );
  }
}
