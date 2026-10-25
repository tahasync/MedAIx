import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/features/share/data/share_repository.dart';
import 'package:tahasync_medaix/features/share/providers/share_providers.dart';
import 'package:tahasync_medaix/features/share/ui/countdown.dart';
import 'package:tahasync_medaix/features/share/ui/doctor_portal_screen.dart';
import 'package:tahasync_medaix/features/share/ui/share_screen.dart';

import 'support/test_app.dart';

/// A clock the test moves by hand; shared by the repository and the
/// countdown so both agree on "now".
class FakeClock {
  DateTime now = DateTime(2026, 10, 25, 20, 0);

  void advance(Duration d) => now = now.add(d);
}

Widget shareScreen(FakeClock clock, {Size size = const Size(390, 844)}) =>
    testScreen(
      const ShareScreen(),
      size: size,
      overrides: <Override>[
        ...fakeOverrides(
          share: FakeShareRepository(
            latency: Duration.zero,
            clock: () => clock.now,
          ),
        ),
        clockProvider.overrideWithValue(() => clock.now),
      ],
    );

void main() {
  group('formatCountdown', () {
    test('formats mm:ss with padding', () {
      expect(formatCountdown(Duration.zero), '00:00');
      expect(formatCountdown(const Duration(seconds: 5)), '00:05');
      expect(
        formatCountdown(const Duration(minutes: 28, seconds: 14)),
        '28:14',
      );
      expect(formatCountdown(const Duration(minutes: 60)), '60:00');
    });

    test('never goes negative', () {
      expect(formatCountdown(const Duration(seconds: -30)), '00:00');
    });
  });

  test('describeRemaining speaks minutes', () {
    expect(describeRemaining(const Duration(seconds: 40)), 'under a minute');
    expect(
      describeRemaining(const Duration(minutes: 1, seconds: 59)),
      '1 minute',
    );
    expect(describeRemaining(const Duration(minutes: 29)), '29 minutes');
  });

  group('ShareScreen', () {
    testWidgets('empty → Create code → active → Revoke → empty', (
      tester,
    ) async {
      await usePhone(tester);
      final FakeClock clock = FakeClock();
      await tester.pumpWidget(shareScreen(clock));
      await tester.pumpAndSettle();

      expect(find.text('Share with doctor'), findsOneWidget);
      expect(find.text('No active codes'), findsOneWidget);
      expect(find.text('15 min'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('60 min'), findsOneWidget);

      await tester.tap(find.text('Create code'));
      await tester.pumpAndSettle();

      expect(find.byType(QrCard), findsOneWidget);
      expect(find.text('Expires in 30:00'), findsOneWidget);
      expect(find.text('Revoke access now'), findsOneWidget);
      expect(find.text('Code created for 30 minutes'), findsOneWidget);
      expect(find.text('Open doctor portal preview'), findsOneWidget);

      await tester.tap(find.text('Revoke access now'));
      await tester.pumpAndSettle();

      expect(find.byType(QrCard), findsNothing);
      expect(find.text('No active codes'), findsOneWidget);
      expect(find.text('Access revoked'), findsOneWidget);
    });

    testWidgets('duration chips are single-select and drive the code', (
      tester,
    ) async {
      await usePhone(tester);
      final FakeClock clock = FakeClock();
      await tester.pumpWidget(shareScreen(clock));
      await tester.pumpAndSettle();

      AppChip chip(String label) =>
          tester.widget(find.widgetWithText(AppChip, label));
      expect(chip('30 min').selected, isTrue);
      expect(chip('15 min').selected, isFalse);

      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      expect(chip('15 min').selected, isTrue);
      expect(chip('30 min').selected, isFalse);

      await tester.tap(find.text('Create code'));
      await tester.pumpAndSettle();
      expect(find.text('Expires in 15:00'), findsOneWidget);
      expect(find.text('Code created for 15 minutes'), findsOneWidget);
    });

    testWidgets('countdown ticks and returns to empty at zero', (tester) async {
      await usePhone(tester);
      final FakeClock clock = FakeClock();
      await tester.pumpWidget(shareScreen(clock));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create code'));
      await tester.pumpAndSettle();
      expect(find.text('Expires in 30:00'), findsOneWidget);

      clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Expires in 29:59'), findsOneWidget);

      clock.advance(const Duration(minutes: 29, seconds: 59));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(QrCard), findsNothing);
      expect(find.text('No active codes'), findsOneWidget);
    });

    testWidgets('active state fits 320 dp without overflow', (tester) async {
      await usePhone(tester, size: const Size(320, 640));
      final FakeClock clock = FakeClock();
      await tester.pumpWidget(shareScreen(clock, size: const Size(320, 640)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create code'));
      await tester.pumpAndSettle();

      expect(find.byType(QrCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('DoctorPortalScreen', () {
    testWidgets('shows read-only access and the two records', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(
        testScreen(
          const DoctorPortalScreen(code: 'MDX-demo'),
          overrides: fakeOverrides(
            share: FakeShareRepository(latency: Duration.zero),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Doctor portal'), findsOneWidget);
      expect(find.textContaining('Read-only access'), findsOneWidget);
      expect(find.textContaining('left'), findsOneWidget);
      expect(find.text('Muhammad'), findsOneWidget);
      expect(find.text('Diabetes · Peanut allergy'), findsOneWidget);
      expect(find.text('Shared records'), findsOneWidget);
      expect(find.text('Blood test, 18 Oct'), findsOneWidget);
      expect(find.text('Current medicines (3)'), findsOneWidget);
      expect(
        find.text(
          'This view is logged. The patient can revoke it at any time.',
        ),
        findsOneWidget,
      );
    });
  });
}
