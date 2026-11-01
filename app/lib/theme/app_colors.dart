/// Single source of colour for MedAIx (design/medaix-mockup.html; see
/// docs/design-system.md §2).
///
/// Widgets never use hex literals; they read `context.colors.<token>`. The two
/// palettes are authored independently rather than inverted, and the brand
/// palette ([Brand]) stays the source for the UI tokens while the semantic
/// ok / warn / error colours are kept separate from it.
library;

import 'package:flutter/material.dart';

/// The five locked brand hexes. Decorative use only; UI colour comes from
/// [AppColors].
abstract final class Brand {
  static const Color ink = Color(0xFF0E0D15);
  static const Color navy = Color(0xFF182346);
  static const Color steel = Color(0xFF3D5387);
  static const Color slate = Color(0xFF7C83AD);
  static const Color mauve = Color(0xFFBFA9BA);
}

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surface2,
    required this.surfaceModal,
    required this.primary,
    required this.onPrimary,
    required this.text,
    required this.muted,
    required this.ok,
    required this.warn,
    required this.error,
    required this.hairline,
    required this.outlineStrong,
    required this.ai,
    required this.aiFill,
    required this.onAiFill,
    required this.viewfinder,
    required this.onViewfinder,
    required this.scanFrame,
    required this.qrInk,
    required this.qrPaper,
  });

  /// Page background.
  final Color background;

  /// Cards and tiles.
  final Color surface;

  /// Nav, chips, ghost buttons, icon tiles, and the AI insight card.
  final Color surface2;
  final Color surfaceModal;

  /// Filled buttons, selected chips, the active nav item, progress fill.
  final Color primary;

  /// Text and icons on [primary].
  final Color onPrimary;

  /// Body text.
  final Color text;

  /// Secondary text. Still ≥ 4.5:1 on [background] and [surface].
  final Color muted;

  /// Semantic status colours. Never used alone: always paired with an icon
  /// and a word ([StatusLabel]).
  final Color ok;
  final Color warn;
  final Color error;

  /// 1 px list dividers.
  final Color hairline;
  final Color outlineStrong;
  final Color ai;
  final Color aiFill;
  final Color onAiFill;
  Color get aiTint =>
      Color.alphaBlend(ai.withValues(alpha: isDark ? 0.10 : 0.04), surface);
  Color get aiGlow => const Color(0x409333EA);

  /// Scanner viewfinder backdrop and its foreground; identical in both
  /// themes because the camera feed behind it is dark.
  final Color viewfinder;
  final Color onViewfinder;

  /// Scan frame and sweep line inside the viewfinder.
  final Color scanFrame;

  /// QR module colour and the white paper it sits on (never themed: scanners
  /// need dark on light).
  final Color qrInk;
  final Color qrPaper;

  /// Dark palette, mockup `.ph[data-t=d]`.
  static const AppColors dark = AppColors(
    background: Color(0xFF0E1726),
    surface: Color(0xFF1E293B),
    surface2: Color(0xFF273449),
    surfaceModal: Color(0xFF334155),
    primary: Color(0xFFA8B0D5),
    onPrimary: Color(0xFF0E1726),
    text: Color(0xFFF1F5F9),
    muted: Color(0xFFA3B1C6),
    ok: Color(0xFF34D399),
    warn: Color(0xFFFBBF24),
    error: Color(0xFFF87171),
    hairline: Color(0xFF334155),
    outlineStrong: Color(0xFF8A99AE),
    ai: Color(0xFFBDA7FF),
    aiFill: Color(0xFF9333EA),
    onAiFill: Color(0xFFFFFFFF),
    viewfinder: Color(0xFF05050A),
    onViewfinder: Color(0xFFFFFFFF),
    scanFrame: Color(0xFFBFA9BA),
    qrInk: Color(0xFF0E0D15),
    qrPaper: Color(0xFFFFFFFF),
  );

  /// Light palette, mockup `.ph[data-t=l]`.
  static const AppColors light = AppColors(
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFE8EDF4),
    surfaceModal: Color(0xFFFFFFFF),
    primary: Color(0xFF182346),
    onPrimary: Color(0xFFFFFFFF),
    text: Color(0xFF0F172A),
    muted: Color(0xFF475569),
    ok: Color(0xFF047857),
    warn: Color(0xFF92400E),
    error: Color(0xFFB91C1C),
    hairline: Color(0xFFE2E8F0),
    outlineStrong: Color(0xFF64748B),
    ai: Color(0xFF6D45E8),
    aiFill: Color(0xFF6D45E8),
    onAiFill: Color(0xFFFFFFFF),
    viewfinder: Color(0xFF05050A),
    onViewfinder: Color(0xFFFFFFFF),
    scanFrame: Color(0xFFBFA9BA),
    qrInk: Color(0xFF0E0D15),
    qrPaper: Color(0xFFFFFFFF),
  );

  bool get isDark => background.computeLuminance() < 0.5;

  /// Translucent tint of [warn] used by the offline banner
  /// (`color-mix(warn 18%, transparent)` in the mockup).
  Color get warnTint => warn.withValues(alpha: 0.18);

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surface2,
    Color? surfaceModal,
    Color? primary,
    Color? onPrimary,
    Color? text,
    Color? muted,
    Color? ok,
    Color? warn,
    Color? error,
    Color? hairline,
    Color? outlineStrong,
    Color? ai,
    Color? aiFill,
    Color? onAiFill,
    Color? viewfinder,
    Color? onViewfinder,
    Color? scanFrame,
    Color? qrInk,
    Color? qrPaper,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surfaceModal: surfaceModal ?? this.surfaceModal,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      ok: ok ?? this.ok,
      warn: warn ?? this.warn,
      error: error ?? this.error,
      hairline: hairline ?? this.hairline,
      outlineStrong: outlineStrong ?? this.outlineStrong,
      ai: ai ?? this.ai,
      aiFill: aiFill ?? this.aiFill,
      onAiFill: onAiFill ?? this.onAiFill,
      viewfinder: viewfinder ?? this.viewfinder,
      onViewfinder: onViewfinder ?? this.onViewfinder,
      scanFrame: scanFrame ?? this.scanFrame,
      qrInk: qrInk ?? this.qrInk,
      qrPaper: qrPaper ?? this.qrPaper,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surface2: mix(surface2, other.surface2),
      surfaceModal: mix(surfaceModal, other.surfaceModal),
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      ok: mix(ok, other.ok),
      warn: mix(warn, other.warn),
      error: mix(error, other.error),
      hairline: mix(hairline, other.hairline),
      outlineStrong: mix(outlineStrong, other.outlineStrong),
      ai: mix(ai, other.ai),
      aiFill: mix(aiFill, other.aiFill),
      onAiFill: mix(onAiFill, other.onAiFill),
      viewfinder: mix(viewfinder, other.viewfinder),
      onViewfinder: mix(onViewfinder, other.onViewfinder),
      scanFrame: mix(scanFrame, other.scanFrame),
      qrInk: mix(qrInk, other.qrInk),
      qrPaper: mix(qrPaper, other.qrPaper),
    );
  }
}

extension AppColorsContext on BuildContext {
  /// The active palette. Every widget reads colour through this.
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
