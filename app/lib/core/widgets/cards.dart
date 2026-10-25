import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import 'app_card.dart';
import 'buttons.dart';

/// Mockup `.card.ai`: `surface2` card with a sparkle tag, h2 title, muted
/// body and a small primary button.
class AiInsightCard extends StatelessWidget {
  const AiInsightCard({
    super.key,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.tag = 'AI insight',
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return AppCard(
      tone: CardTone.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardTag(icon: LucideIcons.sparkles, label: tag),
          Text(title, style: text.titleLarge),
          const SizedBox(height: AppSpace.sm),
          Text(body, style: text.bodyMedium?.copyWith(color: c.muted)),
          const SizedBox(height: AppSpace.lg),
          PrimaryButton(label: actionLabel, onPressed: onAction, compact: true),
        ],
      ),
    );
  }
}

/// Mockup QR tile: 200 px code on a white (`qrPaper`) plate with 12 px
/// padding and radius 20. The pattern is derived from [seed] so the same
/// code always draws the same; it is a visual stand-in until a real QR
/// encoder is wired up (`qr_flutter` is not in the approved list).
class QrCard extends StatelessWidget {
  const QrCard({
    super.key,
    required this.seed,
    required this.semanticLabel,
    this.size = AppSize.qr,
  });

  final int seed;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: semanticLabel,
      image: true,
      child: Center(
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(AppSize.qrPadding),
          decoration: BoxDecoration(
            color: c.qrPaper,
            borderRadius: AppRadius.qrAll,
          ),
          child: CustomPaint(
            painter: _QrPainter(seed: seed, ink: c.qrInk),
          ),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter({required this.seed, required this.ink});

  final int seed;
  final Color ink;

  static const int _n = 21;

  bool _finder(int x, int y) =>
      (x < 7 && y < 7) || (x > 13 && y < 7) || (x < 7 && y > 13);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = ink;
    final double cell = size.width / _n;
    int r = seed & 0x7fffffff;
    for (int y = 0; y < _n; y++) {
      for (int x = 0; x < _n; x++) {
        bool on;
        if (_finder(x, y)) {
          final int a = x > 13 ? x - 14 : x;
          final int b = y > 13 ? y - 14 : y;
          on =
              a == 0 ||
              a == 6 ||
              b == 0 ||
              b == 6 ||
              (a >= 2 && a <= 4 && b >= 2 && b <= 4);
        } else {
          r = (r * 1103515245 + 12345) & 0x7fffffff;
          on = r % 100 < 48;
        }
        if (on) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) =>
      old.seed != seed || old.ink != ink;
}

/// A tappable summary row inside a card: icon tile, bold title, muted
/// subtitle, chevron. Used for "Latest report" on Home and the doctor
/// portal's shared records.
class SummaryRow extends StatelessWidget {
  const SummaryRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final Widget icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      child: Row(
        children: [
          icon,
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: text.bodySmall?.copyWith(color: c.muted),
                  ),
              ],
            ),
          ),
          if (onTap != null)
            ExcludeSemantics(
              child: Icon(
                LucideIcons.chevronRight,
                size: AppSize.icon,
                color: c.text,
              ),
            ),
        ],
      ),
    );
  }
}
