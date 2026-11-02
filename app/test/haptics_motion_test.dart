import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tahasync_medaix/core/brand/brand.dart';
import 'package:tahasync_medaix/core/widgets/app_banner.dart';
import 'package:tahasync_medaix/core/widgets/buttons.dart';
import 'package:tahasync_medaix/core/widgets/chips_and_status.dart';
import 'package:tahasync_medaix/core/widgets/feedback.dart';
import 'package:tahasync_medaix/core/widgets/floating_nav.dart';
import 'package:tahasync_medaix/core/widgets/pressable.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/features/settings/providers/settings_providers.dart';
import 'package:tahasync_medaix/theme/app_theme.dart';
import 'support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('haptics', () {
    test('loads and persists the user preference', () async {
      final FakeSettingsRepository settings = FakeSettingsRepository(
        hapticsEnabled: false,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: fakeOverrides(settings: settings),
      );
      addTearDown(container.dispose);

      expect(await container.read(hapticsEnabledProvider.future), isFalse);
      expect(container.read(appHapticsProvider).enabled, isFalse);

      await container.read(hapticsEnabledProvider.notifier).setEnabled(true);
      expect(settings.hapticsEnabled, isTrue);
      expect(container.read(appHapticsProvider).enabled, isTrue);
    });

    test('disabled cues are silent and rapid cues are rate limited', () async {
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final AppHaptics haptics = AppHaptics()..enabled = false;
      haptics.tap();
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty);

      haptics.enabled = true;
      haptics.select();
      haptics.select();
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'HapticFeedback.vibrate');
      expect(calls.single.arguments, 'HapticFeedbackType.selectionClick');
    });

    test('maps each user event to its documented platform cue', () async {
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final AppHaptics haptics = AppHaptics();
      final List<void Function()> events = <void Function()>[
        haptics.tap,
        haptics.select,
        haptics.toggle,
        haptics.confirm,
        haptics.success,
        haptics.warning,
        haptics.error,
        haptics.refresh,
      ];
      for (final event in events) {
        event();
        await Future<void>.delayed(const Duration(milliseconds: 65));
      }

      expect(
        calls.map((call) => call.method),
        everyElement('HapticFeedback.vibrate'),
      );
      expect(calls.map((call) => call.arguments), <String>[
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.heavyImpact',
        'HapticFeedbackType.lightImpact',
      ]);
    });

    testWidgets(
      'shared controls map actions and passive abnormal values stay silent',
      (tester) async {
        final List<MethodCall> calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'HapticFeedback.vibrate') calls.add(call);
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final AppHaptics haptics = AppHaptics();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...fakeOverrides(),
              appHapticsProvider.overrideWithValue(haptics),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: Column(
                  children: [
                    PrimaryButton(label: 'Save', onPressed: () {}),
                    AppSwitch(
                      value: false,
                      label: 'Preference',
                      onChanged: (_) {},
                    ),
                    const StatusLabel(status: ValueStatus.error, text: 'High'),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 65)),
        );
        await tester.tap(find.bySemanticsLabel('Preference'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 65)),
        );

        expect(calls.map((call) => call.arguments), <String>[
          'HapticFeedbackType.lightImpact',
          'HapticFeedbackType.selectionClick',
        ]);
        expect(find.text('High'), findsOneWidget);
      },
    );

    testWidgets('changing navigation tabs emits a light impact cue', (
      tester,
    ) async {
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...fakeOverrides(),
            appHapticsProvider.overrideWithValue(AppHaptics()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: FloatingNav(
                  items: const <NavItem>[
                    NavItem(icon: Icons.home, label: 'Home'),
                    NavItem(icon: Icons.description, label: 'Reports'),
                  ],
                  selectedIndex: 0,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reports'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 65)),
      );

      expect(calls, hasLength(1));
      expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
    });
  });

  testWidgets('reduced motion keeps skeletons static and durations at zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeOverrides(),
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: ShimmerScope(child: SkeletonBox())),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(SkeletonBox), findsOneWidget);
    expect(
      AppMotion.of(tester.element(find.byType(SkeletonBox)), AppMotion.slow),
      Duration.zero,
    );
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion settles shared animated components', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeOverrides(),
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ListView(
                children: [
                  const Pressable(child: Text('press')),
                  const FadeIn(child: Text('fade')),
                  const StateSwitcher(child: Text('state')),
                  AppSwitch(value: false, label: 'Switch', onChanged: (_) {}),
                  const ProgressBar(value: 0.6),
                  const ScoreRing(value: 0.6, semanticLabel: 'Score'),
                  const FloatingNav(
                    items: <NavItem>[
                      NavItem(icon: Icons.home, label: 'Home'),
                      NavItem(icon: Icons.person, label: 'Profile'),
                    ],
                    selectedIndex: 0,
                    onSelected: _ignoreIndex,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduced motion settles banner and skips boot splash delay', (
    tester,
  ) async {
    await tester.pumpWidget(
      testScreen(const Scaffold(body: AppBanner()), disableAnimations: true),
    );
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(AppBanner)),
    );
    container.read(appBannerProvider.notifier).showInfo('Update available');
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(
      testScreen(
        const BootSplash(child: Text('Ready')),
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });
}

void _ignoreIndex(int _) {}
