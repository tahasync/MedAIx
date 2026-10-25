import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/features/wellness/ui/wellness_screen.dart';

import 'support/test_app.dart';

Widget wellnessScreen({double textScale = 1}) => testScreen(
  const WellnessScreen(),
  textScale: textScale,
  overrides: fakeOverrides(
    wellness: FakeWellnessRepository(latency: Duration.zero),
  ),
);

void main() {
  test('formatThousands adds separators', () {
    expect(formatThousands(0), '0');
    expect(formatThousands(999), '999');
    expect(formatThousands(4120), '4,120');
    expect(formatThousands(1234567), '1,234,567');
  });

  testWidgets('renders the three habit cards and the score', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(wellnessScreen());
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.textContaining('Habit score'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('750 / 2400 ml'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);
    expect(
      find.text('4,120 / 6,000 · goal set for your condition'),
      findsOneWidget,
    );
    expect(find.text('Exercise'), findsOneWidget);
    expect(find.text('Not logged yet'), findsOneWidget);
    expect(find.byType(ProgressBar), findsNWidgets(2));
  });

  testWidgets('+250 ml updates the text and toasts', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(wellnessScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add 250 ml'));
    await tester.pumpAndSettle();

    expect(find.text('1000 / 2400 ml'), findsOneWidget);
    expect(find.text('Added 250 ml of water'), findsOneWidget);
  });

  testWidgets('Log walk shows Logged', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(wellnessScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log walk'));
    await tester.pumpAndSettle();

    expect(find.text('Log walk'), findsNothing);
    expect(find.text('Logged'), findsOneWidget);
    expect(find.text('Walk'), findsOneWidget);
    expect(find.text('Walk logged'), findsOneWidget);
  });

  testWidgets('survives 200 % text scale without overflow', (tester) async {
    await usePhone(tester);
    await tester.pumpWidget(wellnessScreen(textScale: 2));
    await tester.pumpAndSettle();

    expect(find.text('Water'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits 320 dp at 200 % text scale', (tester) async {
    await usePhone(tester, size: const Size(320, 640));
    await tester.pumpWidget(wellnessScreen(textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
