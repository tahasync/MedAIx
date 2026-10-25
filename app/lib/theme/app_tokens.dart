/// Non-colour design tokens: spacing, radii, sizes, motion, type.
/// Values come straight from design/medaix-mockup.html (§2 of the UI master
/// prompt). Widgets reference these instead of magic numbers.
library;

import 'package:flutter/widgets.dart';

/// Spacing. The mockup is on an 8-ish grid with 18 px screen/card padding.
abstract final class AppSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 20;
  static const double xxxl = 24;
  static const double huge = 32;

  /// Horizontal page padding and card padding.
  static const double screen = 18;
  static const double card = 18;

  /// Vertical gap between stacked cards.
  static const double cardGap = 12;

  /// Gap inside the 2 × 2 tile grid.
  static const double gridGap = 10;

  /// Gap between wrapped chips.
  static const double chipGap = 8;

  /// Space below the screen header.
  static const double headerGap = 18;

  /// Space above an `h3` section heading and below it.
  static const double sectionTop = 20;
  static const double sectionBottom = 10;

  /// Readable max width for content on tablets.
  static const double contentMaxWidth = 560;
}

/// Corner radii.
abstract final class AppRadius {
  static const double card = 24;
  static const double tile = 22;
  static const double button = 24;
  static const double chip = 17;
  static const double iconTile = 14;
  static const double nav = 32;
  static const double navItem = 26;
  static const double bar = 4;
  static const double skeleton = 12;
  static const double banner = 16;
  static const double toast = 18;
  static const double qr = 20;
  static const double emptyIcon = 22;
  static const double viewfinder = 26;
  static const double input = 16;

  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius tileAll = BorderRadius.all(Radius.circular(tile));
  static const BorderRadius buttonAll = BorderRadius.all(
    Radius.circular(button),
  );
  static const BorderRadius chipAll = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius iconTileAll = BorderRadius.all(
    Radius.circular(iconTile),
  );
  static const BorderRadius navAll = BorderRadius.all(Radius.circular(nav));
  static const BorderRadius navItemAll = BorderRadius.all(
    Radius.circular(navItem),
  );
  static const BorderRadius barAll = BorderRadius.all(Radius.circular(bar));
  static const BorderRadius skeletonAll = BorderRadius.all(
    Radius.circular(skeleton),
  );
  static const BorderRadius bannerAll = BorderRadius.all(
    Radius.circular(banner),
  );
  static const BorderRadius toastAll = BorderRadius.all(Radius.circular(toast));
  static const BorderRadius qrAll = BorderRadius.all(Radius.circular(qr));
  static const BorderRadius emptyIconAll = BorderRadius.all(
    Radius.circular(emptyIcon),
  );
  static const BorderRadius viewfinderAll = BorderRadius.all(
    Radius.circular(viewfinder),
  );
  static const BorderRadius inputAll = BorderRadius.all(Radius.circular(input));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// Hit targets and component dimensions.
abstract final class AppSize {
  /// Minimum touch target for buttons and icon buttons.
  static const double button = 48;
  static const double iconButton = 48;

  /// Small inline button (`.btn.s`).
  static const double buttonSmall = 44;

  /// Chips: 34 by default, 44 where they are the main control.
  static const double chip = 34;
  static const double chipLarge = 44;
  static const double chipPaddingX = 13;

  /// Floating bottom nav.
  static const double navHeight = 64;
  static const double navItemHeight = 52;
  static const double navItemWidth = 56;

  /// Active indicator: a stadium behind the icon, label beneath it.
  static const double navIndicatorHeight = 32;
  static const double navIndicatorWidth = 64;

  /// Gap kept between the indicator and the slot edge on narrow screens.
  static const double navIndicatorGap = 2;
  static const double navInset = 14;
  static const double navPaddingX = 6;

  /// Bottom padding every scroll view adds so content clears the nav
  /// (mockup `padding-bottom: 110px`).
  static const double navClearance = navInset + navHeight + 32;

  /// Quick-action tile and icon tile.
  static const double tile = 92;
  static const double iconTile = 40;
  static const double iconTileIcon = 20;
  static const double emptyIconTile = 64;
  static const double emptyIcon = 28;

  /// Linear progress bar.
  static const double progressBar = 8;

  /// Switch track and thumb.
  static const double switchWidth = 52;
  static const double switchHeight = 30;
  static const double switchThumb = 24;

  /// QR code.
  static const double qr = 200;
  static const double qrPadding = 12;

  /// Habit-score ring.
  static const double ring = 64;
  static const double ringStroke = 4;

  /// Scanner viewfinder height.
  static const double viewfinder = 300;

  /// Icon sizes.
  static const double icon = 20;
  static const double iconSmall = 16;
  static const double iconTiny = 14;
  static const double iconTileLarge = 22;
  static const double statusIcon = 15;

  /// Minimum layout width the UI must survive without overflow.
  static const double minWidth = 320;
}

/// Motion: 150–250 ms, ease-out. Durations are read through [of] so
/// `MediaQuery.disableAnimations` collapses them to zero.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 250);
  static const Duration shimmer = Duration(milliseconds: 1300);
  static const Duration toast = Duration(milliseconds: 1800);

  static const Curve curve = Curves.easeOut;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Type scale (Figtree). Line heights are ratios as in the mockup CSS.
abstract final class AppType {
  static const String family = 'Figtree';

  static const double h1Size = 28;
  static const FontWeight h1Weight = FontWeight.w700;
  static const double h1Height = 1.15;
  static const double h1Tracking = -0.4;

  static const double h2Size = 19;
  static const FontWeight h2Weight = FontWeight.w600;
  static const double h2Height = 1.25;

  static const double h3Size = 16;
  static const FontWeight h3Weight = FontWeight.w600;
  static const double h3Height = 1.3;

  static const double bodySize = 15;
  static const FontWeight bodyWeight = FontWeight.w400;
  static const double bodyHeight = 1.45;

  static const double smallSize = 13;
  static const double smallHeight = 1.4;

  static const double buttonSize = 16;
  static const FontWeight buttonWeight = FontWeight.w600;

  static const double chipSize = 13;
  static const FontWeight chipWeight = FontWeight.w500;

  static const double navLabelSize = 11;
  static const FontWeight navLabelWeight = FontWeight.w500;

  static const double statusSize = 13;
  static const FontWeight statusWeight = FontWeight.w600;
}

/// The one shadow in the app, under the floating nav
/// (`0 6px 20px rgba(0,0,0,.18)`).
abstract final class AppShadow {
  static const List<BoxShadow> nav = <BoxShadow>[
    BoxShadow(color: Color(0x2E000000), offset: Offset(0, 6), blurRadius: 20),
  ];
}
