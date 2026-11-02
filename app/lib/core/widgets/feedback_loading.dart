/// Reusable feedback widgets, organized by state and loading responsibility.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Mockup `.bar`: 8 high track on `surface2`, primary fill, radius 4.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.semanticLabel,
    this.height = AppSize.progressBar,
  });

  /// 0–1.
  final double value;
  final String? semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final double v = value.clamp(0.0, 1.0);
    return Semantics(
      container: true,
      label: semanticLabel,
      value: '${(v * 100).round()}%',
      child: ClipRRect(
        borderRadius: AppRadius.barAll,
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Container(color: c.surface2),
                AnimatedContainer(
                  duration: AppMotion.of(context, AppMotion.slow),
                  curve: AppMotion.curve,
                  width: constraints.maxWidth * v,
                  color: c.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shares one shimmer ticker across every skeleton on the current screen.
class ShimmerScope extends StatefulWidget {
  const ShimmerScope({super.key, required this.child});

  final Widget child;

  static Animation<double>? maybeAnimationOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ShimmerScopeData>()
      ?.animation;

  @override
  State<ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<ShimmerScope>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.shimmer,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncMotion();
    } else {
      _controller.stop(canceled: false);
    }
  }

  void _syncMotion() {
    final bool canAnimate =
        !AppMotion.reduced(context) &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!canAnimate) {
      _controller.stop(canceled: false);
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ShimmerScopeData(animation: _controller, child: widget.child);
}

class _ShimmerScopeData extends InheritedWidget {
  const _ShimmerScopeData({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_ShimmerScopeData oldWidget) =>
      animation != oldWidget.animation;
}

/// Mockup `.sk`: a placeholder block that shimmers between `surface` and
/// `surface2`. Static under reduced motion.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.height = 16,
    this.width,
    this.radius = AppRadius.skeleton,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Animation<double>? animation = ShimmerScope.maybeAnimationOf(context);
    if (animation == null || AppMotion.reduced(context)) {
      return RepaintBoundary(
        child: Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: c.surface2,
          ),
        ),
      );
    }
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final double t = animation.value;
            return Container(
              height: height,
              width: width,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: LinearGradient(
                  begin: Alignment(-1 - 2 * (1 - t) * 1.5, 0),
                  end: Alignment(1 + 2 * t * 1.5, 0),
                  colors: [c.surface, c.surface2, c.surface],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A skeleton that stands in for a whole card (same radius and height).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 88});

  final double height;

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(height: height, radius: AppRadius.card);
}

/// Mockup `.empty`: centred 64 px icon tile, h2 title, one-line reason,
/// then the primary (and optional ghost) action.
