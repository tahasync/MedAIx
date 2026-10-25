import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import 'app_card.dart';
import 'buttons.dart';
import 'tiles.dart';

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

/// Mockup `.sk`: a placeholder block that shimmers between `surface` and
/// `surface2`. Static under reduced motion.
class SkeletonBox extends StatefulWidget {
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
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.shimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final double t = _controller.value;
          return Container(
            height: widget.height,
            width: widget.width,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(-1 - 2 * (1 - t) * 1.5, 0),
                end: Alignment(1 + 2 * t * 1.5, 0),
                colors: [c.surface, c.surface2, c.surface],
              ),
            ),
          );
        },
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
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.reason,
    this.action,
    this.secondaryAction,
  });

  final IconData icon;
  final String title;
  final String reason;
  final Widget? action;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.card,
        26,
        AppSpace.card,
        AppSpace.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: IconTile(
              icon: icon,
              size: AppSize.emptyIconTile,
              iconSize: AppSize.emptyIcon,
              radius: AppRadius.emptyIcon,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(title, textAlign: TextAlign.center, style: text.titleLarge),
          const SizedBox(height: AppSpace.sm),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
          if (action != null) ...[const SizedBox(height: AppSpace.lg), action!],
          if (secondaryAction != null) ...[
            const SizedBox(height: AppSpace.lg),
            secondaryAction!,
          ],
        ],
      ),
    );
  }
}

/// Mockup `uerr` card: error tag, plain-language message that says whether
/// the user's data is safe, then recovery actions. Never a raw exception.
class ErrorCard extends StatelessWidget {
  const ErrorCard({
    super.key,
    required this.title,
    required this.message,
    this.dataSafety = 'Nothing was changed, and your existing data is safe.',
    this.primaryLabel = 'Try again',
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String message;

  /// The data-safety line. Pass an empty string to omit it when the message
  /// already says so.
  final String dataSafety;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String body = dataSafety.isEmpty ? message : '$message $dataSafety';
    return Semantics(
      liveRegion: true,
      container: true,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardTag(
              icon: LucideIcons.alertTriangle,
              label: title,
              color: c.error,
            ),
            Text(body, style: text.bodyMedium),
            if (onPrimary != null) ...[
              const SizedBox(height: AppSpace.lg),
              PrimaryButton(label: primaryLabel, onPressed: onPrimary),
            ],
            if (onSecondary != null && secondaryLabel != null) ...[
              const SizedBox(height: AppSpace.lg),
              GhostButton(label: secondaryLabel!, onPressed: onSecondary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mockup `.ban`: warn-tinted pill banner. Shown above the header when the
/// device is offline; the caller decides when.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    this.message = 'You’re offline. Changes are saved and will sync later.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.cardGap),
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: AppSpace.md + 2,
        ),
        decoration: BoxDecoration(
          color: c.warnTint,
          borderRadius: AppRadius.bannerAll,
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                LucideIcons.wifiOff,
                size: AppSize.iconSmall,
                color: c.text,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        onTap: onChanged == null ? null : () => onChanged!(!value),
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
                      color: value ? c.onPrimary : c.text,
                      shape: BoxShape.circle,
                    ),
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

/// Habit-score ring (mockup home card): 64 px, 4 px stroke, `surface2`
/// track and primary arc, labelled for screen readers.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.value,
    required this.semanticLabel,
    this.size = AppSize.ring,
  });

  /// 0–1.
  final double value;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: semanticLabel,
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: AppMotion.of(context, AppMotion.slow),
          curve: AppMotion.curve,
          builder: (context, v, _) => CustomPaint(
            painter: _RingPainter(
              value: v,
              track: c.surface2,
              fill: c.primary,
              stroke: AppSize.ringStroke,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.track,
    required this.fill,
    required this.stroke,
  });

  final double value;
  final Color track;
  final Color fill;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Rect arc = rect.deflate(stroke / 2 + 2);
    final Paint trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    final Paint fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = fill;
    canvas.drawArc(arc, 0, 6.283185307, false, trackPaint);
    canvas.drawArc(arc, -1.5707963, 6.283185307 * value, false, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}
