import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import '../connectivity.dart';
import 'buttons.dart';
import 'feedback.dart';

/// Mockup `.hd`: h1 title, optional muted small subtitle, optional trailing
/// widget (an icon button), 18 px below.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.showBack = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Prefix a back button (sub-routes pushed on a tab).
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.headerGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showBack) ...[
            AppIconButton(
              icon: LucideIcons.arrowLeft,
              label: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: AppSpace.lg),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: text.headlineMedium),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xxs),
                    child: Text(
                      subtitle!,
                      style: text.bodySmall?.copyWith(color: c.muted),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.lg),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Mockup `h3`: 16/600 section heading with 20 px above and 10 px below.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.first = false});

  final String text;

  /// No top margin when it is the first thing under the header.
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: first ? 0 : AppSpace.sectionTop,
        bottom: AppSpace.sectionBottom,
      ),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

/// The page frame every screen uses.
///
/// Provides the 18 px screen padding, the offline banner, the shared bottom
/// inset that clears the floating nav ([AppSize.navClearance]), optional
/// pull-to-refresh, and a readable max width on tablets. Content is always
/// scrollable so nothing clips at 320 dp or 200 % text scale.
class AppScreen extends ConsumerWidget {
  const AppScreen({
    super.key,
    required this.children,
    this.header,
    this.onRefresh,
    this.insetForNav = true,
    this.showOfflineBanner = true,
    this.controller,
    this.bottom,
  });

  final Widget? header;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  /// False on screens shown without the nav (onboarding, sign-in).
  final bool insetForNav;
  final bool showOfflineBanner;
  final ScrollController? controller;

  /// Pinned below the scroll view (e.g. a sticky action). Rare.
  final Widget? bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool offline =
        showOfflineBanner && ref.watch(isOfflineProvider).valueOrNull == true;
    final double bottomInset = insetForNav
        ? AppSize.navClearance
        : AppSpace.xxxl + MediaQuery.paddingOf(context).bottom;

    Widget list = ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpace.screen,
        AppSpace.md,
        AppSpace.screen,
        bottomInset,
      ),
      children: [if (offline) const OfflineBanner(), ?header, ...children],
    );

    if (onRefresh != null) {
      list = RefreshIndicator(
        onRefresh: onRefresh!,
        color: context.colors.text,
        backgroundColor: context.colors.surface2,
        child: list,
      );
    }

    Widget body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpace.contentMaxWidth),
        child: list,
      ),
    );

    if (bottom != null) {
      body = Column(
        children: [
          Expanded(child: body),
          bottom!,
        ],
      );
    }

    return SafeArea(bottom: !insetForNav, child: body);
  }
}

/// `Scaffold` with the app background and no app bar; screens inside the
/// nav shell use this, sub-routes may pass [appBar] for a back arrow.
class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key, required this.body, this.appBar});

  final Widget body;
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: appBar,
      resizeToAvoidBottomInset: true,
      body: body,
    );
  }
}

/// Adds the shared nav clearance to any custom scroll view.
extension NavInsetPadding on EdgeInsets {
  static EdgeInsets screen({bool insetForNav = true}) => EdgeInsets.fromLTRB(
    AppSpace.screen,
    AppSpace.md,
    AppSpace.screen,
    insetForNav ? AppSize.navClearance : AppSpace.xxxl,
  );
}

/// A whole-screen loading placeholder matching the real layout size: header
/// line, then [rows] skeleton cards.
class ScreenSkeleton extends StatelessWidget {
  const ScreenSkeleton({super.key, this.rows = 3, this.firstHeight = 88});

  final int rows;
  final double firstHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonCard(height: firstHeight),
        for (int i = 0; i < rows; i++) ...[
          const SizedBox(height: AppSpace.gridGap),
          const SkeletonBox(height: 56),
        ],
      ],
    );
  }
}
