/// Reusable feedback widgets, organized by state and loading responsibility.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import 'pressable.dart';

/// Mockup `.tg`: 52 × 30 switch, thumb 24, primary track when on. Exposes
/// `Semantics(toggled:)` and a 48 px hit target.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Read by screen readers; not drawn.
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Duration d = AppMotion.of(context, AppMotion.normal);
    return Semantics(
      label: label,
      toggled: value,
      enabled: onChanged != null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null
            ? null
            : () {
                playHaptic(context, (haptics) => haptics.toggle());
                onChanged!(!value);
              },
        child: SizedBox(
          width: AppSize.switchWidth,
          height: AppSize.button,
          child: Center(
            child: AnimatedContainer(
              duration: d,
              curve: AppMotion.curve,
              width: AppSize.switchWidth,
              height: AppSize.switchHeight,
              decoration: BoxDecoration(
                color: value ? c.primary : c.surface2,
                borderRadius: AppRadius.pill,
                border: value
                    ? null
                    : Border.all(color: c.outlineStrong, width: 2),
              ),
              child: AnimatedAlign(
                duration: d,
                curve: AppMotion.curve,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    width: AppSize.switchThumb,
                    height: AppSize.switchThumb,
                    decoration: BoxDecoration(
                      color: value ? c.onPrimary : c.muted,
                      shape: BoxShape.circle,
                    ),
                    child: value
                        ? Icon(LucideIcons.check, size: 12, color: c.primary)
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mockup `#toast`: 1.8 s floating plate above the nav. Use this instead of
/// `ScaffoldMessenger.showSnackBar` directly so every toast looks the same.
void showToast(BuildContext context, String message, {SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: AppMotion.toast,
        action: action,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xl,
          vertical: AppSpace.lg,
        ),
      ),
    );
}
