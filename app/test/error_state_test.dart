import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';

import 'support/test_app.dart';

void main() {
  final variants = <(String, ErrorState, String, String, String?)>[
    (
      'not found',
      ErrorState.notFound(onPrimary: () {}),
      'We couldn’t find that page',
      'Go to Home',
      null,
    ),
    (
      'report unavailable',
      ErrorState.reportUnavailable(onPrimary: () {}),
      'This report isn’t available',
      'Back to reports',
      null,
    ),
    (
      'server error',
      ErrorState.serverError(onPrimary: () {}, onSecondary: () {}),
      'Something went wrong on our side',
      'Try again',
      'Contact support',
    ),
    (
      'permission denied',
      ErrorState.permissionDenied(onPrimary: () {}, onSecondary: () {}),
      'MedAIx needs camera access to scan',
      'Open settings',
      'Choose from gallery',
    ),
    (
      'session expired',
      ErrorState.sessionExpired(onPrimary: () {}),
      'Please sign in again',
      'Sign in',
      null,
    ),
    (
      'parse failed',
      ErrorState.parseFailed(onPrimary: () {}, onSecondary: () {}),
      'We couldn’t read this report',
      'Scan again',
      'Choose from gallery',
    ),
  ];

  for (final (name, state, title, primary, secondary) in variants) {
    testWidgets('renders $name copy and recovery actions', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(testScreen(state));
      await tester.pumpAndSettle();

      expect(find.text(title), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget);
      expect(find.text(primary), findsOneWidget);
      if (secondary != null) expect(find.text(secondary), findsOneWidget);
      expect(
        find.byType(GhostButton),
        secondary == null ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('slow-operation hint keeps its child and changes after 8/25 s', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      testScreen(
        SlowOperationHint(
          pending: true,
          onRetry: () => retries++,
          child: const SkeletonBox(height: 96),
        ),
      ),
    );

    expect(find.byType(SkeletonBox), findsOneWidget);
    expect(find.text('Waking up MedAIx…'), findsNothing);
    await tester.pump(kSlowOperationWakingDelay);
    expect(find.text('Waking up MedAIx…'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    await tester.pump(kSlowOperationRetryDelay - kSlowOperationWakingDelay);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(retries, 1);
    expect(find.byType(SkeletonBox), findsOneWidget);
    expect(find.text('Waking up MedAIx…'), findsNothing);
  });

  testWidgets('server error support action opens the support sheet', (
    tester,
  ) async {
    await usePhone(tester);
    await tester.pumpWidget(
      testScreen(
        Builder(
          builder: (context) => ErrorState.serverError(
            onPrimary: () {},
            onSecondary: () => showSupportSheet(context),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Contact support'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Email synctaha@gmail.com'), findsOneWidget);
    expect(find.text('We reply within two working days.'), findsOneWidget);
  });

  test('slow-operation timer transitions at the configured thresholds', () {
    fakeAsync((clock) {
      final stages = <SlowOperationStage>[];
      final timer = SlowOperationTimer(stages.add);
      timer.start();
      expect(stages, <SlowOperationStage>[SlowOperationStage.normal]);

      clock.elapse(kSlowOperationWakingDelay);
      expect(stages.last, SlowOperationStage.waking);
      clock.elapse(kSlowOperationRetryDelay - kSlowOperationWakingDelay);
      expect(stages.last, SlowOperationStage.stillWaiting);
      timer.cancel();
    });
  });

  test(
    'user-facing code does not interpolate raw exception toString output',
    () {
      final Directory lib = Directory('lib');
      final List<File> dartFiles = lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      for (final File file in dartFiles) {
        final String source = file.readAsStringSync();
        expect(
          RegExp(r'\b(?:error|exception|e)\.toString\(\)').hasMatch(source),
          isFalse,
          reason: '${file.path} may expose a raw exception to users',
        );
      }
    },
  );
}
