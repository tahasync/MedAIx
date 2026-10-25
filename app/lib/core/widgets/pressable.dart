import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Haptic cues for primary actions and selections.
abstract final class AppHaptics {
  static void primary() => HapticFeedback.lightImpact();
  static void select() => HapticFeedback.selectionClick();
  static void success() => HapticFeedback.mediumImpact();
  static void error() => HapticFeedback.heavyImpact();
}

/// Scales its child to 98 % while pressed. Layout bounds do not change, so
/// neighbours never jitter. Honours reduced motion.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (!widget.enabled || _down == down) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.98 : 1,
        duration: AppMotion.of(context, AppMotion.fast),
        curve: AppMotion.curve,
        child: widget.child,
      ),
    );
  }
}

/// Fades a child in when it first appears (no slide; respects reduced
/// motion). Used for state changes inside a screen, not page entrances.
class FadeIn extends StatelessWidget {
  const FadeIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.of(context, AppMotion.slow),
      curve: AppMotion.curve,
      child: child,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
    );
  }
}

/// Cross-fades between states with the design-system timing.
class StateSwitcher extends StatelessWidget {
  const StateSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.slow),
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      // Children get the parent's (width-tight) constraints, so a card or a
      // Wrap of chips fills the row exactly as it would outside the switcher
      // instead of shrinking to its content and floating in the centre.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.passthrough,
        alignment: AlignmentDirectional.topStart,
        children: [...previousChildren, ?currentChild],
      ),
      child: child,
    );
  }
}
