import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'pressable.dart';

/// Which tone a card sits on. Depth comes from tone, never from shadow.
enum CardTone {
  /// `surface` — ordinary cards and tiles.
  surface,

  /// `surface2` — the AI insight card and anything that must read as
  /// "interactive/accent" without a border.
  raised,
}

/// Mockup `.card`: radius 24, padding 18, no border, no shadow.
///
/// Pass [onTap] for a tappable card (ripple clipped to the corners, 98 %
/// press scale, button semantics).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.tone = CardTone.surface,
    this.padding = const EdgeInsets.all(AppSpace.card),
    this.onTap,
    this.semanticLabel,
    this.color,
  });

  final Widget child;
  final CardTone tone;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Overrides the tone colour. Only for the QR paper tile.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color fill =
        color ?? (tone == CardTone.raised ? c.surface2 : c.surface);

    Widget body = Padding(padding: padding, child: child);
    if (onTap != null) {
      body = InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardAll,
        child: body,
      );
    }

    Widget card = Material(
      color: fill,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
      child: body,
    );

    if (onTap != null) {
      card = Pressable(child: card);
    }
    if (semanticLabel != null || onTap != null) {
      card = Semantics(
        button: onTap != null,
        label: semanticLabel,
        container: true,
        child: card,
      );
    }
    return card;
  }
}

/// A `.tag` line: small icon + 13/600 label, used above card titles
/// ("AI insight", "In plain words", "Couldn't read this photo").
class CardTag extends StatelessWidget {
  const CardTag({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;

  /// Defaults to the text colour. Pass a status colour for warnings and
  /// errors; the icon and word carry the meaning, not the colour alone.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color fg = color ?? context.colors.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: AppSize.iconSmall, color: fg),
          ),
          const SizedBox(width: AppSpace.sm),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
