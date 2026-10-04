/// MedAIx theme — brand palette per the MedAIx Color System review.
///
/// Five locked brand hexes (Ink / Navy / Steel / Slate / Mauve) drive both
/// `ColorScheme`s. Each theme is authored independently rather than inverted,
/// and alert states live in [AppSemanticColors] because `ColorScheme` has no
/// warning/success roles.
library;

import 'package:flutter/material.dart';

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.surfaceVariant,
    required this.outlineSoft,
  });

  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  /// A step off the base surface — grouped sections and glass backing.
  final Color surfaceVariant;

  /// Low-contrast dividers.
  final Color outlineSoft;

  @override
  AppSemanticColors copyWith({
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? surfaceVariant,
    Color? outlineSoft,
  }) {
    return AppSemanticColors(
      error: error ?? this.error,
      onError: onError ?? this.onError,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      outlineSoft: outlineSoft ?? this.outlineSoft,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer: Color.lerp(onErrorContainer, other.onErrorContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      outlineSoft: Color.lerp(outlineSoft, other.outlineSoft, t)!,
    );
  }
}

/// Convenience accessor so widgets read `context.semantic.error` instead of
/// casting the extension by hand.
extension AppSemanticColorsContext on BuildContext {
  AppSemanticColors get semantic =>
      Theme.of(this).extension<AppSemanticColors>()!;
}
class AppTheme {
  const AppTheme._();

  // Locked brand hexes.
  static const Color ink = Color(0xFF0E0D15);
  static const Color navy = Color(0xFF182346);
  static const Color steel = Color(0xFF3D5387);
  static const Color slate = Color(0xFF7C83AD);
  static const Color mauve = Color(0xFFBFA9BA);

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: steel,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDCE0E9),
    onPrimaryContainer: navy,
    secondary: slate,
    onSecondary: ink,
    secondaryContainer: Color(0xFFE2E4ED),
    onSecondaryContainer: navy,
    tertiary: mauve,
    onTertiary: ink,
    tertiaryContainer: Color(0xFFE2D8E0),
    onTertiaryContainer: ink,
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF4DEDD),
    onErrorContainer: Color(0xFFB3261E),
    surface: Color(0xFFF7F8FA),
    onSurface: ink,
    surfaceContainerHighest: Color(0xFFDCE0E9),
    onSurfaceVariant: Color(0xFF70769C),
    outline: Color(0xFF70769C),
    outlineVariant: Color(0xFFD6D9E4),
    shadow: ink,
    scrim: ink,
    inverseSurface: navy,
    onInverseSurface: Color(0xFFF7F8FA),
    inversePrimary: slate,
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: slate,
    onPrimary: ink,
    primaryContainer: Color(0xFF161E3A),
    onPrimaryContainer: mauve,
    secondary: mauve,
    onSecondary: ink,
    secondaryContainer: Color(0xFF273660),
    onSecondaryContainer: Color(0xFFD2C3CF),
    tertiary: Color(0xFF818FB1),
    onTertiary: ink,
    tertiaryContainer: Color(0xFF232C48),
    onTertiaryContainer: Color(0xFFB1BACF),
    error: Color(0xFFD58883),
    onError: ink,
    errorContainer: Color(0xFF371317),
    onErrorContainer: Color(0xFFD58883),
    surface: Color(0xFF121526),
    onSurface: Color(0xFFE2D8E0),
    surfaceContainerHighest: Color(0xFF232C48),
    onSurfaceVariant: Color(0xFF898FB5),
    outline: Color(0xFF898FB5),
    outlineVariant: Color(0xFF2C2F45),
    shadow: ink,
    scrim: ink,
    inverseSurface: Color(0xFFE2D8E0),
    onInverseSurface: Color(0xFF0E0D15),
    inversePrimary: steel,
  );

  static const AppSemanticColors _lightSemantics = AppSemanticColors(
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF4DEDD),
    onErrorContainer: Color(0xFFB3261E),
    warning: Color(0xFF8A5200),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFEDE5D9),
    onWarningContainer: Color(0xFF8A5200),
    success: Color(0xFF1E6B3D),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDDE9E2),
    onSuccessContainer: Color(0xFF1E6B3D),
    surfaceVariant: Color(0xFFF0F1F5),
    outlineSoft: Color(0xFFD6D9E4),
  );

  static const AppSemanticColors _darkSemantics = AppSemanticColors(
    error: Color(0xFFD58883),
    onError: ink,
    errorContainer: Color(0xFF371317),
    onErrorContainer: Color(0xFFD58883),
    warning: Color(0xFFBFA073),
    onWarning: ink,
    warningContainer: Color(0xFF2D1E10),
    onWarningContainer: Color(0xFFBFA073),
    success: Color(0xFF83AE94),
    onSuccess: ink,
    successContainer: Color(0xFF12241F),
    onSuccessContainer: Color(0xFF83AE94),
    surfaceVariant: Color(0xFF181B2E),
    outlineSoft: Color(0xFF2C2F45),
  );

  static ThemeData get light => _base(_lightScheme, _lightSemantics);
  static ThemeData get dark => _base(_darkScheme, _darkSemantics);

  static ThemeData _base(ColorScheme scheme, AppSemanticColors semantics) {
    final bool isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Color System: dark is the signature experience — deep Ink background, never
      // black; light stays calm and spacious — never pure white. `scheme.surface`
      // is the *elevated* tier (`#121526` in dark), not the page background.
      scaffoldBackgroundColor: isDark ? ink : scheme.surface,
      cardTheme: CardThemeData(
        elevation: 1,
        color: isDark ? semantics.surfaceVariant : const Color(0xFFFFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? ink : scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: semantics.outlineSoft),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: semantics.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: semantics.outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? ink : scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 2,
        height: 68,
      ),
      dividerTheme: DividerThemeData(
        color: semantics.outlineSoft,
        space: 1,
        thickness: 1,
      ),
      extensions: <ThemeExtension<dynamic>>[semantics],
    );
  }
}