/// Material 3 [ThemeData] for both palettes, built entirely from
/// [AppColors] and the tokens in `app_tokens.dart`.
///
/// Flat, minimal, production design: no gradients, no blur, no translucent
/// surfaces, no elevation anywhere except the floating nav (which draws its
/// own shadow). Depth comes from tone â€” `surface` on `background`.
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

export 'app_colors.dart';
export 'app_tokens.dart';

abstract final class AppTheme {
  static ThemeData get light => build(AppColors.light);
  static ThemeData get dark => build(AppColors.dark);

  /// Figtree is bundled under `assets/fonts/` (declared in pubspec), so the
  /// type renders identically offline and on first launch â€” no runtime
  /// fetch. Falls back to the platform sans if the asset is missing.
  static const List<String> _fallback = <String>['Roboto', 'sans-serif'];

  static TextTheme textTheme(AppColors c) {
    TextStyle style({
      required double size,
      required FontWeight weight,
      required double height,
      double tracking = 0,
      Color? color,
    }) {
      return TextStyle(
        fontFamily: AppType.family,
        fontFamilyFallback: _fallback,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: tracking,
        color: color ?? c.text,
      );
    }

    final TextStyle h1 = style(
      size: AppType.h1Size,
      weight: AppType.h1Weight,
      height: AppType.h1Height,
      tracking: AppType.h1Tracking,
    );
    final TextStyle h2 = style(
      size: AppType.h2Size,
      weight: AppType.h2Weight,
      height: AppType.h2Height,
    );
    final TextStyle h3 = style(
      size: AppType.h3Size,
      weight: AppType.h3Weight,
      height: AppType.h3Height,
    );
    final TextStyle body = style(
      size: AppType.bodySize,
      weight: AppType.bodyWeight,
      height: AppType.bodyHeight,
    );
    final TextStyle small = style(
      size: AppType.smallSize,
      weight: AppType.bodyWeight,
      height: AppType.smallHeight,
    );
    final TextStyle button = style(
      size: AppType.buttonSize,
      weight: AppType.buttonWeight,
      height: 1.2,
    );
    final TextStyle label = style(
      size: AppType.chipSize,
      weight: AppType.chipWeight,
      height: 1.2,
    );
    final TextStyle labelSmall = style(
      size: AppType.navLabelSize,
      weight: AppType.navLabelWeight,
      height: 1.2,
    );

    return TextTheme(
      displaySmall: h1.copyWith(fontSize: 34),
      headlineLarge: h1.copyWith(fontSize: 32),
      headlineMedium: h1,
      headlineSmall: h1.copyWith(fontSize: 24),
      titleLarge: h2,
      titleMedium: h3,
      titleSmall: h3.copyWith(fontSize: 15),
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: small,
      labelLarge: button,
      labelMedium: label,
      labelSmall: labelSmall,
    );
  }

  static ThemeData build(AppColors c) {
    final Brightness brightness = c.isDark ? Brightness.dark : Brightness.light;
    final TextTheme text = textTheme(c);

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.surface2,
      onPrimaryContainer: c.text,
      secondary: c.surface2,
      onSecondary: c.text,
      secondaryContainer: c.surface2,
      onSecondaryContainer: c.text,
      tertiary: c.muted,
      onTertiary: c.background,
      tertiaryContainer: c.surface2,
      onTertiaryContainer: c.text,
      error: c.error,
      onError: c.onPrimary,
      errorContainer: c.surface2,
      onErrorContainer: c.error,
      surface: c.surface,
      onSurface: c.text,
      surfaceDim: c.background,
      surfaceBright: c.surface2,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.background,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surface2,
      surfaceContainerHighest: c.surface2,
      onSurfaceVariant: c.muted,
      outline: c.hairline,
      outlineVariant: c.hairline,
      shadow: Brand.ink,
      scrim: Brand.ink,
      inverseSurface: c.text,
      onInverseSurface: c.background,
      inversePrimary: c.onPrimary,
      surfaceTint: Colors.transparent,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: AppType.family,
      textTheme: text,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );

    final RoundedRectangleBorder pill = const RoundedRectangleBorder(
      borderRadius: AppRadius.buttonAll,
    );

    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      cardColor: c.surface,
      dividerColor: c.hairline,
      disabledColor: c.muted,
      hintColor: c.muted,
      focusColor: c.text.withValues(alpha: 0.12),
      hoverColor: c.text.withValues(alpha: 0.06),
      highlightColor: c.text.withValues(alpha: 0.08),
      splashColor: c.text.withValues(alpha: 0.10),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: c.text, size: AppSize.icon + 2),
        toolbarHeight: 56,
      ),
      iconTheme: IconThemeData(color: c.text, size: AppSize.icon),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          disabledBackgroundColor: c.primary.withValues(alpha: 0.5),
          disabledForegroundColor: c.onPrimary.withValues(alpha: 0.7),
          minimumSize: const Size(AppSize.button, AppSize.button),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
          shape: pill,
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          minimumSize: const Size(AppSize.button, AppSize.button),
          shape: pill,
          textStyle: text.labelLarge,
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: c.surface2,
          foregroundColor: c.text,
          minimumSize: const Size(AppSize.button, AppSize.button),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
          shape: pill,
          side: BorderSide.none,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.text,
          minimumSize: const Size(AppSize.button, AppSize.button),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.text,
          minimumSize: const Size(AppSize.iconButton, AppSize.iconButton),
          shape: const CircleBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xl,
          vertical: AppSpace.xl,
        ),
        labelStyle: text.bodyMedium?.copyWith(color: c.muted),
        floatingLabelStyle: text.labelMedium?.copyWith(color: c.text),
        hintStyle: text.bodyMedium?.copyWith(color: c.muted),
        helperStyle: text.bodySmall?.copyWith(color: c.muted),
        errorStyle: text.bodySmall?.copyWith(color: c.error),
        prefixIconColor: c.muted,
        suffixIconColor: c.muted,
        border: const UnderlineInputBorder(
          borderRadius: AppRadius.inputAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const UnderlineInputBorder(
          borderRadius: AppRadius.inputAll,
          borderSide: BorderSide.none,
        ),
        focusedBorder: UnderlineInputBorder(
          borderRadius: AppRadius.inputAll,
          borderSide: BorderSide(color: c.text, width: 2),
        ),
        errorBorder: UnderlineInputBorder(
          borderRadius: AppRadius.inputAll,
          borderSide: BorderSide(color: c.error, width: 1.5),
        ),
        focusedErrorBorder: UnderlineInputBorder(
          borderRadius: AppRadius.inputAll,
          borderSide: BorderSide(color: c.error, width: 2),
        ),
        disabledBorder: const UnderlineInputBorder(
          borderRadius: AppRadius.inputAll,
          borderSide: BorderSide.none,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface2,
        selectedColor: c.primary,
        disabledColor: c.surface2.withValues(alpha: 0.5),
        side: BorderSide.none,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
        labelStyle: text.labelMedium?.copyWith(color: c.text),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: c.onPrimary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSize.chipPaddingX,
          vertical: AppSpace.md,
        ),
        showCheckmark: false,
        iconTheme: IconThemeData(color: c.text, size: AppSize.iconTiny),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.muted),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpace.card,
          0,
          AppSpace.card,
          AppSpace.card,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: c.hairline,
        dragHandleSize: const Size(40, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      // Toast (mockup `#toast`): text-coloured plate, background-coloured
      // copy, floating above the nav.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.text,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: c.background,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: c.background,
        closeIconColor: c.background,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.toastAll),
        insetPadding: const EdgeInsets.fromLTRB(
          AppSpace.xxxl,
          0,
          AppSpace.xxxl,
          AppSize.navInset + AppSize.navHeight + AppSpace.xl,
        ),
        elevation: 0,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surface2,
        circularTrackColor: Colors.transparent,
        linearMinHeight: AppSize.progressBar,
        borderRadius: AppRadius.barAll,
      ),
      dividerTheme: DividerThemeData(color: c.hairline, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: c.text,
        textColor: c.text,
        titleTextStyle: text.bodyMedium,
        subtitleTextStyle: text.bodySmall?.copyWith(color: c.muted),
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: AppSpace.lg,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.onPrimary : c.text,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.primary : c.surface2,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(c.onPrimary),
        side: BorderSide(color: c.muted, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.primary : c.muted,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.text,
          borderRadius: AppRadius.skeletonAll,
        ),
        textStyle: text.bodySmall?.copyWith(color: c.background),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.text,
        selectionColor: c.primary.withValues(alpha: 0.3),
        selectionHandleColor: c.primary,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(BorderSide.none),
          shape: WidgetStatePropertyAll(pill),
          textStyle: WidgetStatePropertyAll(text.labelMedium),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? c.primary : c.surface2,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? c.onPrimary : c.text,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? c.onPrimary : c.text,
          ),
          minimumSize: const WidgetStatePropertyAll(
            Size(AppSize.button, AppSize.chipLarge),
          ),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[c],
    );
  }
}
