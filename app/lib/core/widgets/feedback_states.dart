/// Reusable feedback widgets, organized by state and loading responsibility.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import '../brand/brand.dart';
import '../legal/legal_constants.dart';
import 'app_card.dart';
import 'buttons.dart';
import 'tiles.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.reason,
    this.action,
    this.secondaryAction,
  });

  final IconData icon;
  final String title;
  final String reason;
  final Widget? action;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.card,
        26,
        AppSpace.card,
        AppSpace.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: IconTile(
              icon: icon,
              size: AppSize.emptyIconTile,
              iconSize: AppSize.emptyIcon,
              radius: AppRadius.emptyIcon,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(title, textAlign: TextAlign.center, style: text.titleLarge),
          const SizedBox(height: AppSpace.sm),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
          if (action != null) ...[const SizedBox(height: AppSpace.lg), action!],
          if (secondaryAction != null) ...[
            const SizedBox(height: AppSpace.lg),
            secondaryAction!,
          ],
        ],
      ),
    );
  }
}

/// Mockup `uerr` card: error tag, plain-language message that says whether
/// the user's data is safe, then recovery actions. Never a raw exception.
class ErrorCard extends StatelessWidget {
  const ErrorCard({
    super.key,
    required this.title,
    required this.message,
    this.dataSafety = 'Nothing was changed, and your existing data is safe.',
    this.primaryLabel = 'Try again',
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String message;

  /// The data-safety line. Pass an empty string to omit it when the message
  /// already says so.
  final String dataSafety;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) => ErrorState(
    key: key,
    title: title,
    body: dataSafety.isEmpty ? message : '$message $dataSafety',
    primaryLabel: primaryLabel,
    onPrimary: onPrimary,
    secondaryLabel: secondaryLabel,
    onSecondary: onSecondary,
    icon: LucideIcons.alertTriangle,
  );
}

/// A complete recovery state for a dead end or failed screen.
///
/// The supplied body starts with what happened and states whether existing
/// data is safe before offering an action. Named constructors use the copy
/// catalogue in docs/prd-ux-refresh.md Appendix C.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    required this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.icon = LucideIcons.alertTriangle,
  });

  factory ErrorState.notFound({Key? key, VoidCallback? onPrimary}) =>
      ErrorState(
        key: key,
        title: 'We couldn’t find that page',
        body: 'The link may be old. Your data is safe.',
        primaryLabel: 'Go to Home',
        onPrimary: onPrimary,
        icon: LucideIcons.fileText,
      );

  factory ErrorState.reportUnavailable({Key? key, VoidCallback? onPrimary}) =>
      ErrorState(
        key: key,
        title: 'This report isn’t available',
        body: 'It may have been deleted, or it belongs to another account.',
        primaryLabel: 'Back to reports',
        onPrimary: onPrimary,
        icon: LucideIcons.fileText,
      );

  factory ErrorState.serverError({
    Key? key,
    VoidCallback? onPrimary,
    VoidCallback? onSecondary,
  }) => ErrorState(
    key: key,
    title: 'Something went wrong on our side',
    body: 'Your data is safe. Please try again.',
    primaryLabel: 'Try again',
    onPrimary: onPrimary,
    secondaryLabel: 'Contact support',
    onSecondary: onSecondary,
    icon: LucideIcons.alertTriangle,
  );

  factory ErrorState.permissionDenied({
    Key? key,
    bool camera = true,
    VoidCallback? onPrimary,
    VoidCallback? onSecondary,
  }) => ErrorState(
    key: key,
    title: camera
        ? 'MedAIx needs camera access to scan'
        : 'MedAIx needs photo access to add a report',
    body: camera
        ? 'You can also choose a photo from your gallery.'
        : 'Allow access in Settings, or choose a photo or PDF from your gallery.',
    primaryLabel: 'Open settings',
    onPrimary: onPrimary,
    secondaryLabel: 'Choose from gallery',
    onSecondary: onSecondary,
    icon: LucideIcons.camera,
  );

  factory ErrorState.sessionExpired({Key? key, VoidCallback? onPrimary}) =>
      ErrorState(
        key: key,
        title: 'Please sign in again',
        body: 'Anything not yet synced is kept on this device.',
        primaryLabel: 'Sign in',
        onPrimary: onPrimary,
        icon: LucideIcons.user,
      );

  factory ErrorState.parseFailed({
    Key? key,
    VoidCallback? onPrimary,
    VoidCallback? onSecondary,
  }) => ErrorState(
    key: key,
    title: 'We couldn’t read this report',
    body: 'Retake the photo in good light with the whole page in frame.',
    primaryLabel: 'Scan again',
    onPrimary: onPrimary,
    secondaryLabel: 'Choose from gallery',
    onSecondary: onSecondary,
    icon: LucideIcons.fileText,
  );

  final String title;
  final String body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: ExcludeSemantics(child: BrandMark(size: 32)),
                ),
                const SizedBox(height: AppSpace.md),
                Center(
                  child: ExcludeSemantics(
                    child: Icon(
                      icon,
                      size: AppSize.iconTileLarge,
                      color: c.warn,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Focus(
                  autofocus: true,
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: text.headlineSmall,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: c.muted),
                ),
                if (primaryLabel != null && onPrimary != null) ...[
                  const SizedBox(height: AppSpace.lg),
                  PrimaryButton(label: primaryLabel!, onPressed: onPrimary),
                ],
                if (secondaryLabel != null && onSecondary != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  GhostButton(label: secondaryLabel!, onPressed: onSecondary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showSupportSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle(
        duration: AppMotion.of(context, AppMotion.normal),
        reverseDuration: AppMotion.of(context, AppMotion.normal),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpace.card),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Contact support',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpace.lg),
              for (var i = 0; i < kSupportParagraphs.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpace.lg),
                Text(kSupportParagraphs[i]),
              ],
              const SizedBox(height: AppSpace.xl),
              PrimaryButton(
                label: 'Got it',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );

/// Mockup `.ban`: warn-tinted pill banner. Shown above the header when the
/// device is offline; the caller decides when.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    this.message = 'You’re offline. Changes are saved and will sync later.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.cardGap),
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: AppSpace.md + 2,
        ),
        decoration: BoxDecoration(
          color: c.warnTint,
          borderRadius: AppRadius.bannerAll,
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                LucideIcons.wifiOff,
                size: AppSize.iconSmall,
                color: c.text,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
