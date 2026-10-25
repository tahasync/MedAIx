import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'pressable.dart';

/// One destination in the [FloatingNav].
class NavItem {
  const NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Mockup `.nav`: 64 high pill on `surface2`, inset 14 from the sides and
/// the bottom, five equal slots. This is the only shadowed surface in the
/// app.
///
/// The active destination is marked by a primary stadium behind its icon
/// with the label beneath in `text`; inactive items are `muted`. Every
/// destination gets an equal share of the bar, so selecting a tab never
/// shifts its neighbours, and the whole slot (64 dp tall) is the hit target.
class FloatingNav extends StatelessWidget {
  const FloatingNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final double safeBottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSize.navInset,
        0,
        AppSize.navInset,
        AppSize.navInset + safeBottom,
      ),
      child: Semantics(
        container: true,
        label: 'Main navigation',
        child: Container(
          height: AppSize.navHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSize.navPaddingX),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: AppRadius.navAll,
            boxShadow: AppShadow.nav,
          ),
          // Nav labels are short by design; cap their scale so the bar keeps
          // its 64 dp height at 200 % system text size.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              // Stretch so each slot is the full 64 dp hit target.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavButton(
                      item: items[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Duration duration = AppMotion.of(context, AppMotion.normal);
    final TextStyle labelStyle = Theme.of(context).textTheme.labelSmall!;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Pressable(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.navItemAll,
            onTap: () {
              if (!selected) AppHaptics.select();
              onTap();
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double indicatorWidth = _indicatorWidth(
                  constraints.maxWidth,
                );
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: duration,
                      curve: AppMotion.curve,
                      width: indicatorWidth,
                      height: AppSize.navIndicatorHeight,
                      decoration: BoxDecoration(
                        color: selected ? c.primary : Colors.transparent,
                        borderRadius: AppRadius.pill,
                      ),
                      child: TweenAnimationBuilder<Color?>(
                        duration: duration,
                        curve: AppMotion.curve,
                        tween: ColorTween(
                          end: selected ? c.onPrimary : c.muted,
                        ),
                        builder: (context, color, _) =>
                            Icon(item.icon, size: AppSize.icon, color: color),
                      ),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    AnimatedDefaultTextStyle(
                      duration: duration,
                      curve: AppMotion.curve,
                      style: labelStyle.copyWith(
                        color: selected ? c.text : c.muted,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(item.label, maxLines: 1, softWrap: false),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 64 wide where the slot allows, otherwise the slot minus a small gap.
  static double _indicatorWidth(double slotWidth) {
    if (!slotWidth.isFinite) return AppSize.navIndicatorWidth;
    return math.min(
      AppSize.navIndicatorWidth,
      slotWidth - 2 * AppSize.navIndicatorGap,
    );
  }
}
