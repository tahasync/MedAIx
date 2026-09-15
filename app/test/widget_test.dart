import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('MedAIx renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MedAIxApp()));
    await tester.pump();
    expect(find.text('MedAIx'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
