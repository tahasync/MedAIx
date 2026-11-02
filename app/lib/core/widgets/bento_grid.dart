/// Responsive, reading-order-preserving two-column bento layout.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'pressable.dart';

class BentoGrid extends StatelessWidget {
  const BentoGrid({super.key, required this.children});

  final List<BentoTile> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final bool oneColumn =
          constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(1) >= 1.5;
      if (oneColumn) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpace.cardGap),
              SizedBox(width: double.infinity, child: children[i]),
            ],
          ],
        );
      }

      final rows = <Widget>[];
      var index = 0;
      while (index < children.length) {
        final first = children[index];
        if (first.span == 2) {
          rows.add(first);
          index++;
        } else if (index + 1 < children.length &&
            children[index + 1].span == 1) {
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: first),
                  const SizedBox(width: AppSpace.cardGap),
                  Expanded(child: children[index + 1]),
                ],
              ),
            ),
          );
          index += 2;
        } else {
          rows.add(
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(widthFactor: 0.5, child: first),
            ),
          );
          index++;
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.cardGap),
            rows[i],
          ],
        ],
      );
    },
  );
}

class BentoTile extends StatelessWidget {
  const BentoTile({
    super.key,
    required this.child,
    this.span = 1,
    this.onTap,
    this.semanticsLabel,
    this.automated = false,
    this.padding = const EdgeInsets.all(AppSpace.card),
  }) : assert(span == 1 || span == 2);

  final int span;
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final bool automated;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color fill = automated ? c.aiTint : c.surface;
    final shape = RoundedRectangleBorder(
      borderRadius: AppRadius.tileAll,
      side: automated
          ? BorderSide(color: c.ai, width: 1.5)
          : c.isDark
          ? BorderSide.none
          : BorderSide(color: c.hairline),
    );
    Widget content = Material(
      color: fill,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 96),
        child: InkWell(
          borderRadius: AppRadius.tileAll,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (onTap != null) content = Pressable(child: content);
    if (semanticsLabel != null || onTap != null) {
      content = Semantics(
        container: true,
        button: onTap != null,
        label: semanticsLabel,
        child: content,
      );
    }
    return content;
  }
}
