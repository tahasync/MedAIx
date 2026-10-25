import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import 'pressable.dart';

/// Mockup `.ico`: 40 px rounded (14) tile on `surface2` behind an icon.
/// Decorative — excluded from semantics.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.size = AppSize.iconTile,
    this.iconSize = AppSize.iconTileIcon,
    this.radius = AppRadius.iconTile,
    this.color,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final double radius;

  /// Icon colour; defaults to text.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Icon(icon, size: iconSize, color: color ?? c.text),
      ),
    );
  }
}

/// Mockup `.tile`: 92 high quick-action button, icon top-left, 15/600 label
/// bottom-left, radius 22, `surface`.
class TileButton extends StatelessWidget {
  const TileButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        child: Material(
          color: c.surface,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.tileAll),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              AppHaptics.select();
              onTap();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSize.tile),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, size: AppSize.iconTileLarge, color: c.text),
                    const SizedBox(height: AppSpace.lg),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Widest a [ListRow.trailing] may be: half the content width inside a card,
/// never less than an icon button.
double _trailingMaxWidth(BuildContext context) {
  final double content =
      MediaQuery.sizeOf(context).width -
      2 * AppSpace.screen -
      2 * AppSpace.card;
  final double half = content / 2;
  return half < AppSize.iconButton ? AppSize.iconButton : half;
}

/// Mockup `.li`: a list row with a hairline divider below (none on the last
/// row). [leading] is usually an [IconTile]; [trailing] defaults to a
/// chevron when the row is tappable.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.isLast = false,
    this.destructive = false,
    this.titleBold = false,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isLast;

  /// Error-coloured title ("Delete my data").
  final bool destructive;

  /// Bold title (report rows, reminder rows).
  final bool titleBold;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color titleColor = destructive ? c.error : c.text;

    Widget row = Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: AppSpace.lg)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.bodyMedium?.copyWith(
                  color: titleColor,
                  fontWeight: titleBold || subtitle != null
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: text.bodySmall?.copyWith(color: c.muted),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpace.lg),
          // Capped at half the row so a long trailing label (a StatusLabel at
          // 200 % text scale on a 320 dp screen) wraps instead of overflowing,
          // while a short switch or chevron keeps its natural width.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _trailingMaxWidth(context)),
            child: trailing!,
          ),
        ] else if (onTap != null) ...[
          const SizedBox(width: AppSpace.lg),
          ExcludeSemantics(
            child: Icon(
              LucideIcons.chevronRight,
              size: AppSize.icon,
              color: c.text,
            ),
          ),
        ],
      ],
    );

    row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
      child: row,
    );

    if (onTap != null) {
      row = InkWell(
        onTap: () {
          AppHaptics.select();
          onTap!();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.button),
          child: row,
        ),
      );
      row = Semantics(
        button: true,
        label:
            semanticLabel ?? (subtitle == null ? title : '$title, $subtitle'),
        excludeSemantics: semanticLabel != null,
        child: row,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: c.hairline, width: 1)),
      ),
      child: row,
    );
  }
}

/// Builds a column of [ListRow]s, setting `isLast` automatically.
class ListRows extends StatelessWidget {
  const ListRows({super.key, required this.rows});

  final List<ListRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < rows.length; i++)
          ListRow(
            key: rows[i].key,
            title: rows[i].title,
            subtitle: rows[i].subtitle,
            leading: rows[i].leading,
            trailing: rows[i].trailing,
            onTap: rows[i].onTap,
            destructive: rows[i].destructive,
            titleBold: rows[i].titleBold,
            semanticLabel: rows[i].semanticLabel,
            isLast: i == rows.length - 1,
          ),
      ],
    );
  }
}
