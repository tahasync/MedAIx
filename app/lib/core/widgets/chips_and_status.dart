import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import 'pressable.dart';

/// Mockup `.ch`: 34 high pill on `surface2`; selected = primary fill with
/// `onPrimary` text and a check mark. [large] makes it the 44 high main
/// control (duration pickers).
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.large = false,
    this.expand = false,
    this.showCheck = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Leading icon when not selected (e.g. "+ Add").
  final IconData? icon;
  final bool large;

  /// Fill the available width (row of equal chips).
  final bool expand;

  /// Show a check mark when selected.
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color bg = selected ? c.primary : c.surface2;
    final Color fg = selected ? c.onPrimary : c.text;
    final IconData? leading = selected && showCheck ? LucideIcons.check : icon;

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[
          ExcludeSemantics(
            child: Icon(leading, size: AppSize.iconTiny, color: fg),
          ),
          const SizedBox(width: AppSpace.sm),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
          ),
        ),
      ],
    );

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        enabled: onTap != null,
        child: Material(
          color: bg,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap == null
                ? null
                : () {
                    AppHaptics.select();
                    onTap!();
                  },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: large ? AppSize.chipLarge : AppSize.chip,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSize.chipPaddingX,
                ),
                child: Center(widthFactor: 1, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Meaning of a value or a report, used by [StatusLabel] and list rows.
enum ValueStatus { ok, warn, error, neutral }

extension ValueStatusX on ValueStatus {
  IconData get icon => switch (this) {
    ValueStatus.ok => LucideIcons.check,
    ValueStatus.warn => LucideIcons.alertTriangle,
    ValueStatus.error => LucideIcons.alertTriangle,
    ValueStatus.neutral => LucideIcons.info,
  };

  Color color(AppColors c) => switch (this) {
    ValueStatus.ok => c.ok,
    ValueStatus.warn => c.warn,
    ValueStatus.error => c.error,
    ValueStatus.neutral => c.muted,
  };
}

/// Mockup `.st`: icon + word in the status colour. Status is never carried
/// by colour alone — the icon and the word always travel with it.
class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.status, required this.text});

  final ValueStatus status;
  final String text;

  @override
  Widget build(BuildContext context) {
    final Color fg = status.color(context.colors);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(status.icon, size: AppSize.statusIcon, color: fg),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: AppType.statusWeight,
              color: fg,
            ),
          ),
        ),
      ],
    );
  }
}
