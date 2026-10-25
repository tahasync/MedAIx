import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'pressable.dart';

/// Mockup `.btn`: 48 high pill, primary fill, full width, 12 px top margin
/// handled by the caller. Shows a spinner and disables itself while
/// [loading].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
    this.compact = false,
    this.haptic = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  /// Full width (the default) or hug content.
  final bool expanded;

  /// `.btn.s`: inline, 44 high, horizontal padding 20.
  final bool compact;

  /// Light impact on press (primary CTAs).
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _ButtonBase(
      label: label,
      icon: icon,
      loading: loading,
      expanded: expanded && !compact,
      compact: compact,
      background: c.primary,
      foreground: c.onPrimary,
      onPressed: onPressed == null || loading
          ? null
          : () {
              if (haptic) AppHaptics.primary();
              onPressed!();
            },
    );
  }
}

/// Mockup `.btn.g`: same geometry as [PrimaryButton] on `surface2`.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expanded;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _ButtonBase(
      label: label,
      icon: icon,
      loading: loading,
      expanded: expanded && !compact,
      compact: compact,
      background: c.surface2,
      foreground: c.text,
      onPressed: onPressed == null || loading ? null : onPressed,
    );
  }
}

/// Text-only action (e.g. "Remind me later"). 48 high for the hit target.
class LinkButton extends StatelessWidget {
  const LinkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: destructive ? c.error : c.text,
      ),
      child: Text(label),
    );
  }
}

class _ButtonBase extends StatelessWidget {
  const _ButtonBase({
    required this.label,
    required this.icon,
    required this.loading,
    required this.expanded,
    required this.compact,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final IconData? icon;
  final bool loading;
  final bool expanded;
  final bool compact;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final double height = compact ? AppSize.buttonSmall : AppSize.button;
    final ButtonStyle style = FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      disabledBackgroundColor: background.withValues(alpha: 0.5),
      disabledForegroundColor: foreground.withValues(alpha: 0.7),
      minimumSize: Size(compact ? 0 : AppSize.button, height),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpace.xxl : AppSpace.xxxl,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.buttonAll),
      textStyle: Theme.of(context).textTheme.labelLarge,
      elevation: 0,
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    final Widget child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: foreground,
            ),
          )
        else if (icon != null)
          ExcludeSemantics(child: Icon(icon, size: AppSize.icon)),
        if (loading || icon != null) const SizedBox(width: AppSpace.md),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    final Widget button = FilledButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );

    return Semantics(
      enabled: onPressed != null,
      child: SizedBox(width: expanded ? double.infinity : null, child: button),
    );
  }
}

/// Mockup `.ib`: 48 px circular icon button on `surface` (or `surface2`
/// when placed on a card). Always labelled.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onCard = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Use `surface2` so the button stays visible on a `surface` card.
  final bool onCard;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: AppSize.icon),
      style: IconButton.styleFrom(
        backgroundColor: onCard ? c.surface2 : c.surface,
        foregroundColor: c.text,
        disabledBackgroundColor: (onCard ? c.surface2 : c.surface).withValues(
          alpha: 0.5,
        ),
        minimumSize: const Size(AppSize.iconButton, AppSize.iconButton),
        fixedSize: const Size(AppSize.iconButton, AppSize.iconButton),
        shape: const CircleBorder(),
      ),
    );
  }
}
