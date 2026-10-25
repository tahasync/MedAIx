/// Reminder switches (mockup `reminders`), persisted on this device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../data/settings_repository.dart';
import '../providers/settings_providers.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final AsyncValue<ReminderSettings> reminders = ref.watch(remindersProvider);
    final RemindersController controller = ref.read(remindersProvider.notifier);

    return AppScaffold(
      body: AppScreen(
        header: const ScreenHeader(
          title: 'Reminders',
          subtitle: 'Delivered on this device',
          showBack: true,
        ),
        children: [
          StateSwitcher(
            child: reminders.when(
              skipLoadingOnReload: true,
              loading: () => const _RemindersSkeleton(key: ValueKey('loading')),
              error: (_, _) => ErrorCard(
                key: const ValueKey('error'),
                title: 'Couldn’t load your reminders',
                message: 'Something went wrong reading your settings.',
                dataSafety:
                    'Your reminder choices are still saved on this '
                    'device.',
                onPrimary: () => ref.invalidate(remindersProvider),
              ),
              data: (value) => AppCard(
                key: const ValueKey('data'),
                child: ListRows(
                  rows: [
                    ListRow(
                      title: 'Take medicines',
                      subtitle: 'Every day at 8:00 am',
                      titleBold: true,
                      trailing: AppSwitch(
                        value: value.medicines,
                        label: 'Take medicines',
                        onChanged: (on) =>
                            controller.save(value.copyWith(medicines: on)),
                      ),
                    ),
                    ListRow(
                      title: 'Drink water',
                      subtitle: 'Every 2 hours, 9 am to 9 pm',
                      titleBold: true,
                      trailing: AppSwitch(
                        value: value.water,
                        label: 'Drink water',
                        onChanged: (on) =>
                            controller.save(value.copyWith(water: on)),
                      ),
                    ),
                    ListRow(
                      title: 'Doctor follow-up',
                      subtitle: '3 days before your visit',
                      titleBold: true,
                      trailing: AppSwitch(
                        value: value.followUp,
                        label: 'Doctor follow-up',
                        onChanged: (on) =>
                            controller.save(value.copyWith(followUp: on)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.cardGap),
          Text(
            'Notification permission is asked the first time you turn a '
            'reminder on.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _RemindersSkeleton extends StatelessWidget {
  const _RemindersSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(
        children: [
          for (int i = 0; i < 3; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
              decoration: BoxDecoration(
                border: i == 2
                    ? null
                    : Border(bottom: BorderSide(color: c.hairline)),
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(height: 16, width: 120),
                        SizedBox(height: AppSpace.sm),
                        SkeletonBox(height: 12, width: 160),
                      ],
                    ),
                  ),
                  SizedBox(width: AppSpace.lg),
                  SkeletonBox(
                    height: AppSize.switchHeight,
                    width: AppSize.switchWidth,
                    radius: AppSize.switchHeight / 2,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
