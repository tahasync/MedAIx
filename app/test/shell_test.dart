import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
