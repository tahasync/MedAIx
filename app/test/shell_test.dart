import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/router.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/theme/app_theme.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('signed-in app boots into the shell with five tabs', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.byType(FloatingNav), findsOneWidget);
    for (final label in ['Home', 'Reports', 'Meds', 'Wellness', 'More']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('signed-out app shows sign-in and no nav', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp(overrides: fakeOverrides(session: null)));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingNav), findsNothing);
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('unknown route shows not found and can go home', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testAppAt('/definitely-missing'));
    await tester.pumpAndSettle();

    expect(find.text('We couldn’t find that page'), findsOneWidget);
    expect(find.text('Go to Home'), findsOneWidget);
    await tester.tap(find.text('Go to Home'));
    await tester.pumpAndSettle();
    expect(find.text('Test'), findsOneWidget);
  });

  testWidgets('unknown route still follows the signed-out redirect', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(
      testAppAt('/definitely-missing', overrides: fakeOverrides(session: null)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.byType(ErrorState), findsNothing);
  });

  testWidgets('not-found back button returns to the previous route', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    final router = ProviderScope.containerOf(
      tester.element(find.byType(FloatingNav)),
    ).read(routerProvider);
    unawaited(router.push('/definitely-missing'));
    await tester.pumpAndSettle();
    expect(find.text('We couldn’t find that page'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Test'), findsOneWidget);
  });

  testWidgets('incomplete profile shows onboarding without the nav', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(
      testApp(overrides: fakeOverrides(profile: kFreshProfile)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingNav), findsNothing);
  });

  testWidgets('tapping a tab switches the branch', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Meds'));
    await tester.pumpAndSettle();
    expect(find.text('Medicine check'), findsOneWidget);
  });

  testWidgets('scroll views clear the floating nav', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    final ListView list = tester.widget(find.byType(ListView).first);
    final EdgeInsets padding = list.padding!.resolve(TextDirection.ltr);
    expect(padding.bottom, greaterThanOrEqualTo(AppSize.navClearance));
  });
}
