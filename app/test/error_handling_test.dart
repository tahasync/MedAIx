import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/error_handling.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('widget error fallback never displays exception text', (
    tester,
  ) async {
    const String privateMessage = 'patient report exception sentinel';
    final Widget fallback = safeErrorWidget(
      FlutterErrorDetails(exception: StateError(privateMessage)),
    );

    await tester.pumpWidget(testScreen(fallback));

    expect(find.text('This screen could not load'), findsOneWidget);
    expect(find.textContaining('saved data remains safe'), findsOneWidget);
    expect(find.textContaining(privateMessage), findsNothing);
  });

  test('unhandled errors activate the recovery surface', () {
    addTearDown(() => unhandledAppError.value = false);
    unhandledAppError.value = false;

    reportUnhandledAppError(
      StateError('private exception details'),
      StackTrace.empty,
    );

    expect(unhandledAppError.value, isTrue);
  });

  testWidgets('global recovery surface hides the underlying app', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    unhandledAppError.value = true;
    await tester.pumpAndSettle();

    expect(find.text('MedAIx needs to recover'), findsOneWidget);
    expect(
      find.text('Something went wrong. Your saved data remains safe.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Return to MedAIx'));
    await tester.pumpAndSettle();
    expect(unhandledAppError.value, isFalse);
  });
}
