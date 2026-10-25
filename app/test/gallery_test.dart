import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/features/gallery/ui/gallery_screen.dart';

import 'support/test_app.dart';

/// Scrolls the gallery to the end so every section is laid out at least
/// once. Skeletons animate forever, so `pumpAndSettle` is avoided.
Future<void> _scrollThrough(WidgetTester tester) async {
  final Finder list = find.byType(ListView).first;
  for (int i = 0; i < 40; i++) {
    await tester.drag(list, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Nav').evaluate().isNotEmpty &&
        find.byType(FloatingNav).evaluate().isNotEmpty) {
      break;
    }
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _renderAt(WidgetTester tester, Size size) async {
  await usePhone(tester, size: size);
  await tester.pumpWidget(testScreen(const GalleryScreen(), size: size));
  await tester.pump();

  expect(find.text('Component gallery'), findsOneWidget);
  expect(find.text('Light'), findsWidgets);
  expect(find.text('Dark'), findsWidgets);

  await _scrollThrough(tester);
  expect(find.byType(FloatingNav), findsNWidgets(2));
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('renders both themes without overflow at 390 dp', (tester) async {
    await _renderAt(tester, const Size(390, 844));
  });

  testWidgets('renders both themes without overflow at 320 dp', (tester) async {
    await _renderAt(tester, const Size(320, 640));
  });

  testWidgets('paints each panel with its own theme background', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(testScreen(const GalleryScreen()));
    await tester.pump();

    final Iterable<Container> panels = tester
        .widgetList<Container>(
          find.ancestor(
            of: find.text('Light'),
            matching: find.byType(Container),
          ),
        )
        .where((c) => c.decoration is BoxDecoration);
    final Iterable<Container> darkPanels = tester
        .widgetList<Container>(
          find.ancestor(
            of: find.text('Dark'),
            matching: find.byType(Container),
          ),
        )
        .where((c) => c.decoration is BoxDecoration);

    expect(panels, isNotEmpty);
    expect(darkPanels, isNotEmpty);
    final Color light = (panels.first.decoration! as BoxDecoration).color!;
    final Color dark = (darkPanels.first.decoration! as BoxDecoration).color!;
    expect(light, isNot(dark));
    expect(light.computeLuminance(), greaterThan(dark.computeLuminance()));
  });
}
