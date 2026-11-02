/// Reusable feedback widgets, organized by state and loading responsibility.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

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
