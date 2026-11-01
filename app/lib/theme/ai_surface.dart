import 'package:flutter/material.dart';

import 'app_theme.dart';

const String kInsightTagLabel = 'Automated insight';

/// The limited, solid treatment for deterministic automated explanations.
class AiSurface extends StatelessWidget {
  const AiSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.card),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.aiTint,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.ai, width: 1.5),
      ),
      child: child,
    );
  }
}

/// Adds the single permitted busy-state glow around an automated action.
class AiBusyAction extends StatelessWidget {
  const AiBusyAction({super.key, required this.busy, required this.child});

  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: busy && c.isDark
            ? <BoxShadow>[BoxShadow(color: c.aiGlow, blurRadius: 16)]
            : const <BoxShadow>[],
      ),
      child: child,
    );
  }
}
