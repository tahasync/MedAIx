/// go_router table and the signed-in shell (§4 of the UI master prompt).
///
/// Five tabs — Home, Reports, Meds, Wellness, More — each a
/// `StatefulShellBranch` so sub-routes keep their parent tab highlighted and
/// their own back stack. The nav is hidden during onboarding and while the
/// keyboard is up. Sign-in and onboarding live outside the shell.
///
/// Public paths follow the prompt (`/upload`, `/report/:id`, `/scan`,
/// `/profile`, …) via redirect aliases onto the nested locations go_router
/// needs to build the branch stack (`/reports/upload`, `/reports/:id`, …),
/// so Back from a sub-route always lands on its tab root.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../features/auth/providers/auth_providers.dart';
import '../features/auth/ui/sign_in_screen.dart';
import '../features/doctor/ui/doctor_screen.dart';
import '../features/gallery/ui/gallery_screen.dart';
import '../features/home/ui/home_screen.dart';
import '../features/meds/ui/meds_screen.dart';
import '../features/meds/ui/scan_screen.dart';
import '../features/onboarding/ui/onboarding_screen.dart';
import '../features/profile/providers/profile_providers.dart';
import '../features/profile/ui/profile_screen.dart';
import '../features/reports/data/reports_repository.dart';
import '../features/reports/ui/report_screen.dart';
import '../features/reports/ui/reports_screen.dart';
import '../features/reports/ui/trends_screen.dart';
import '../features/reports/ui/upload_screen.dart';
import '../features/settings/providers/settings_providers.dart';
import '../features/settings/ui/reminders_screen.dart';
import '../features/settings/ui/settings_screen.dart';
import '../features/share/ui/doctor_portal_screen.dart';
import '../features/share/ui/share_screen.dart';
import '../features/wellness/ui/wellness_screen.dart';
import '../theme/app_theme.dart';
import 'features.dart';
import 'update_checker.dart';
import 'widgets/widgets.dart';

/// Every location in the app. Screens navigate with these, never with
/// string literals.
abstract final class AppRoutes {
  static const String home = '/';
  static const String doctor = '/doctor';
  static const String signIn = '/sign-in';
  static const String onboarding = '/onboarding';
  static const String gallery = '/gallery';

  static const String reports = '/reports';
  static const String upload = '/reports/upload';
  static const String trends = '/reports/trends';
  static String report(int id) => '/reports/$id';

  static const String meds = '/meds';
  static const String scan = '/meds/scan';

  static const String wellness = '/wellness';

  static const String settings = '/settings';
  static const String profile = '/settings/profile';
  static const String reminders = '/settings/reminders';
  static const String share = '/settings/share';
  static const String doctorPortal = '/settings/doctor-portal';
}

/// Navigation helpers used by every screen.
extension AppNavigation on BuildContext {
  /// Back if there is somewhere to go back to, otherwise [fallback]. Keeps
  /// deep links and "Back" from a tab root from exiting the app.
  void popOrGo(String fallback) {
    if (canPop()) {
      pop();
    } else {
      go(fallback);
    }
  }
}

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// The router. Rebuilds its redirects when the session changes; the set of
/// tabs and routes follows [featuresProvider] (sprint gating).
final routerProvider = Provider<GoRouter>((ref) {
  final _RouterRefresh refresh = _RouterRefresh();
  ref.listen(authControllerProvider, (_, _) => refresh.ping());
  ref.onDispose(refresh.dispose);
  final FeatureFlags features = ref.watch(featuresProvider);

  /// A route for a later sprint: registered so deep links resolve, but it
  /// lands on Home until the feature ships.
  String? gate(bool enabled) => enabled ? null : AppRoutes.home;

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final bool signedIn = ref.read(authControllerProvider) != null;
      final String location = state.matchedLocation;
      final bool onSignIn = location == AppRoutes.signIn;
      if (!signedIn && !onSignIn) return AppRoutes.signIn;
      if (signedIn && onSignIn) return AppRoutes.home;
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.gallery,
        builder: (context, state) => const GalleryScreen(),
      ),
      // Public aliases from the prompt onto the nested locations.
      GoRoute(path: '/upload', redirect: (_, _) => AppRoutes.upload),
      GoRoute(path: '/trends', redirect: (_, _) => AppRoutes.trends),
      GoRoute(
        path: '/report/:id',
        redirect: (_, state) => '/reports/${state.pathParameters['id']}',
      ),
      GoRoute(path: '/scan', redirect: (_, _) => AppRoutes.scan),
      GoRoute(path: '/profile', redirect: (_, _) => AppRoutes.profile),
      GoRoute(path: '/reminders', redirect: (_, _) => AppRoutes.reminders),
      GoRoute(path: '/share', redirect: (_, _) => AppRoutes.share),
      GoRoute(
        path: '/doctor-portal',
        redirect: (_, _) => AppRoutes.doctorPortal,
      ),
      // Tabs for epics not yet delivered are not branches, but their paths
      // still resolve (to Home) so stale links never 404.
      if (!features.meds)
        GoRoute(path: AppRoutes.meds, redirect: (_, _) => AppRoutes.home),
      if (!features.meds)
        GoRoute(path: AppRoutes.scan, redirect: (_, _) => AppRoutes.home),
      if (!features.wellness)
        GoRoute(path: AppRoutes.wellness, redirect: (_, _) => AppRoutes.home),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'doctor',
                    redirect: (_, _) => gate(features.doctorMatch),
                    builder: (context, state) => const DoctorScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.reports,
                builder: (context, state) => const ReportsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'upload',
                    builder: (context, state) => const UploadScreen(),
                  ),
                  GoRoute(
                    path: 'trends',
                    redirect: (_, _) => gate(features.trends),
                    builder: (context, state) => TrendsScreen(
                      marker: state.uri.queryParameters['marker'],
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => ReportScreen(
                      id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (features.meds)
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: AppRoutes.meds,
                  builder: (context, state) => const MedsScreen(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'scan',
                      redirect: (_, _) => gate(features.scan),
                      builder: (context, state) => const ScanScreen(),
                    ),
                  ],
                ),
              ],
            ),
          if (features.wellness)
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: AppRoutes.wellness,
                  builder: (context, state) => const WellnessScreen(),
                ),
              ],
            ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'profile',
                    builder: (context, state) => const ProfileScreen(),
                  ),
                  GoRoute(
                    path: 'reminders',
                    redirect: (_, _) => gate(features.reminders),
                    builder: (context, state) => const RemindersScreen(),
                  ),
                  GoRoute(
                    path: 'share',
                    redirect: (_, _) => gate(features.share),
                    builder: (context, state) => const ShareScreen(),
                  ),
                  GoRoute(
                    path: 'doctor-portal',
                    redirect: (_, _) => gate(features.doctorPortal),
                    builder: (context, state) => DoctorPortalScreen(
                      code: state.uri.queryParameters['code'],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// The tabs in nav order for a given set of [features]. Must stay in step
/// with the branch list in [routerProvider].
List<NavItem> navItemsFor(FeatureFlags features) => <NavItem>[
  const NavItem(icon: LucideIcons.home, label: 'Home'),
  const NavItem(icon: LucideIcons.fileText, label: 'Reports'),
  if (features.meds) const NavItem(icon: LucideIcons.pill, label: 'Meds'),
  if (features.wellness)
    const NavItem(icon: LucideIcons.heart, label: 'Wellness'),
  const NavItem(icon: LucideIcons.menu, label: 'More'),
];

/// Signed-in frame: profile gate → onboarding (no nav) or the tab content
/// with the [FloatingNav] floating over it.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final bool seen = ref.watch(onboardingSeenProvider).valueOrNull ?? false;

    return profile.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const _ShellLoading(),
      error: (error, _) => _ShellError(
        message: error is RepositoryException
            ? error.message
            : 'Could not load your profile.',
        onRetry: () => ref.invalidate(profileProvider),
        onSignOut: () => ref.read(authGatewayProvider).signOut(),
      ),
      data: (value) {
        if (!value.onboardingComplete && !seen) {
          return const OnboardingScreen();
        }
        return _ShellBody(shell: shell);
      },
    );
  }
}

class _ShellBody extends ConsumerWidget {
  const _ShellBody({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Once per session, as soon as the tabs are on screen.
    listenForAppUpdates(context, ref);
    final bool keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: context.colors.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: shell),
          if (!keyboardOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingNav(
                items: navItemsFor(ref.watch(featuresProvider)),
                selectedIndex: shell.currentIndex,
                onSelected: (index) => shell.goBranch(
                  index,
                  // Tapping the active tab returns to its root.
                  initialLocation: index == shell.currentIndex,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShellLoading extends StatelessWidget {
  const _ShellLoading();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: AppScreen(
        insetForNav: false,
        showOfflineBanner: false,
        children: const [
          SizedBox(height: AppSpace.huge),
          SkeletonBox(height: 32, width: 180, radius: AppRadius.skeleton),
          SizedBox(height: AppSpace.md),
          SkeletonBox(height: 16, width: 120),
          SizedBox(height: AppSpace.headerGap),
          SkeletonCard(height: 150),
          SizedBox(height: AppSpace.cardGap),
          SkeletonCard(height: 92),
          SizedBox(height: AppSpace.cardGap),
          SkeletonCard(height: 92),
        ],
      ),
    );
  }
}

class _ShellError extends StatelessWidget {
  const _ShellError({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: AppScreen(
        insetForNav: false,
        header: const ScreenHeader(title: 'MedAIx'),
        children: [
          ErrorCard(
            title: 'Couldn’t load your profile',
            message: message,
            dataSafety: 'Your reports are still saved on your account.',
            onPrimary: onRetry,
            secondaryLabel: 'Sign out',
            onSecondary: onSignOut,
          ),
        ],
      ),
    );
  }
}
