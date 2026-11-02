import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tahasync_medaix/core/widgets/app_banner.dart';
import 'package:tahasync_medaix/data/api/api_client.dart';

import 'support/test_app.dart';

void main() {
  group('AppBanner priority and behavior', () {
    testWidgets('shows offline before retrying, update and info', (
      tester,
    ) async {
      await tester.pumpWidget(testScreen(const Scaffold(body: AppBanner())));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppBanner)),
      );
      final controller = container.read(appBannerProvider.notifier);

      controller.showInfo('A helpful note');
      controller.setUpdate(
        message: 'A new version is available',
        onUpdate: () {},
      );
      controller.setRetrying(true);
      await tester.pumpAndSettle();
      expect(find.text('Reconnecting to MedAIx…'), findsOneWidget);

      controller.setDeviceOffline(true);
      await tester.pumpAndSettle();
      expect(find.textContaining('You’re offline'), findsOneWidget);
      expect(find.text('Reconnecting to MedAIx…'), findsNothing);

      controller.setDeviceOffline(false);
      await tester.pumpAndSettle();
      expect(find.text('Reconnecting to MedAIx…'), findsOneWidget);
      controller.setRetrying(false);
      await tester.pumpAndSettle();
      expect(find.text('A new version is available'), findsOneWidget);

      controller.dismiss(AppBannerKind.update);
      await tester.pumpAndSettle();
      expect(find.text('A helpful note'), findsOneWidget);
    });

    testWidgets('update dismissal lasts for the provider session', (
      tester,
    ) async {
      await tester.pumpWidget(testScreen(const Scaffold(body: AppBanner())));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppBanner)),
      );
      final controller = container.read(appBannerProvider.notifier);
      controller.setUpdate(
        message: 'A new version is available',
        onUpdate: () {},
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      controller.setUpdate(
        message: 'A new version is available',
        onUpdate: () {},
      );
      await tester.pumpAndSettle();
      expect(find.text('A new version is available'), findsNothing);
    });

    testWidgets('offline banner cannot be dismissed and actions stay usable', (
      tester,
    ) async {
      var updateTapped = false;
      var screenActionTapped = false;
      await tester.pumpWidget(
        testScreen(
          Scaffold(
            body: Column(
              children: [
                const AppBanner(),
                TextButton(
                  onPressed: () => screenActionTapped = true,
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppBanner)),
      );
      final controller = container.read(appBannerProvider.notifier);
      controller.setDeviceOffline(true);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Dismiss'), findsNothing);

      controller.setDeviceOffline(false);
      controller.setUpdate(
        message: 'A new version is available',
        onUpdate: () => updateTapped = true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update'));
      await tester.pump();
      expect(updateTapped, isTrue);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(screenActionTapped, isTrue);
    });
  });

  test(
    'transport failure shows offline and the next success clears it',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var requests = 0;
      final client = ApiClient(
        baseUrl: 'https://medaix.test',
        client: MockClient((request) async {
          requests++;
          if (requests <= 3) throw http.ClientException('offline');
          return http.Response('{"status":"ok"}', 200);
        }),
        onOfflineChanged: (offline) => container
            .read(appBannerProvider.notifier)
            .setRequestOffline(offline),
        onRetryingChanged: (retrying) =>
            container.read(appBannerProvider.notifier).setRetrying(retrying),
      );
      addTearDown(client.dispose);

      await expectLater(client.checkHealth(), throwsA(isA<ApiException>()));
      expect(
        container.read(appBannerProvider.notifier).current?.kind,
        AppBannerKind.offline,
      );

      expect(await client.checkHealth(), isTrue);
      expect(container.read(appBannerProvider.notifier).current, isNull);
    },
  );
}
