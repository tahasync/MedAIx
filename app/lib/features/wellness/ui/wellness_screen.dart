/// Today (mockup `wellness`): water, steps and exercise cards with the
/// habit score in the header.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/connectivity.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../../home/providers/home_providers.dart';
import '../data/wellness_repository.dart';
import '../providers/wellness_providers.dart';

/// One tap of the water button, as in the mockup.
const int kWaterStepMl = 250;

class WellnessScreen extends ConsumerWidget {
  const WellnessScreen({super.key});

  Future<void> _addWater(BuildContext context, WidgetRef ref) async {
    final bool? ok = await ref
        .read(wellnessProvider.notifier)
        .addWater(kWaterStepMl);
    if (ok == null || !context.mounted) return;
    ref.invalidate(habitTodayProvider);
    showToast(
      context,
      ok
          ? 'Added $kWaterStepMl ml of water'
          : 'Couldn’t log water. Today’s log is unchanged.',
    );
  }

  Future<void> _logWalk(BuildContext context, WidgetRef ref) async {
    final bool? ok = await ref
        .read(wellnessProvider.notifier)
        .logExercise('Walk', minutes: 10);
    if (ok == null || !context.mounted) return;
    ref.invalidate(habitTodayProvider);
    showToast(
      context,
      ok ? 'Walk logged' : 'Couldn’t log your walk. Today’s log is unchanged.',
    );
  }

  Future<void> _logSteps(BuildContext context, WidgetRef ref) async {
    final int? steps = await showDialog<int>(
      context: context,
      builder: (_) => const _LogStepsDialog(),
    );
    if (steps == null || !context.mounted) return;
    final bool? ok = await ref.read(wellnessProvider.notifier).addSteps(steps);
    if (ok == null || !context.mounted) return;
    ref.invalidate(habitTodayProvider);
    showToast(
      context,
      ok
          ? 'Added ${formatThousands(steps)} steps'
          : 'Couldn’t log steps. Today’s log is unchanged.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<WellnessDay> day = ref.watch(wellnessProvider);
    final WellnessDay? value = day.valueOrNull;
    final bool deviceOffline =
        ref.watch(isOfflineProvider).valueOrNull ?? false;

    return AppScaffold(
      body: AppScreen(
        header: ScreenHeader(
          title: 'Today',
          subtitle: value == null ? null : 'Habit score ${value.habitScore}',
        ),
        onRefresh: () => ref.read(wellnessProvider.notifier).refresh(),
        children: day.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const [
            SkeletonCard(height: 116),
            SizedBox(height: AppSpace.cardGap),
            SkeletonCard(height: 116),
            SizedBox(height: AppSpace.cardGap),
            SkeletonCard(height: 96),
          ],
          error: (error, _) => [
            ErrorCard(
              title: 'Couldn’t load today’s habits',
              message: friendlyWellnessError(
                error,
                'We couldn’t reach your habit log.',
              ),
              dataSafety: 'Unsynced entries stay saved on this device.',
              onPrimary: () => ref.read(wellnessProvider.notifier).refresh(),
            ),
          ],
          data: (d) => [
            if (deviceOffline || d.isOffline || d.pendingSyncCount > 0)
              OfflineBanner(
                message: d.pendingSyncCount > 0
                    ? '${d.pendingSyncCount} ${d.pendingSyncCount == 1 ? 'entry is' : 'entries are'} '
                          'saved on this device and will sync when you’re back online.'
                    : 'You’re offline. Your saved log is shown; new entries will sync when you’re back online.',
              ),
            _HabitCard(
              icon: LucideIcons.droplet,
              title: 'Water',
              subtitle: d.waterGoalMl == null
                  ? '${d.waterMl} ml logged · ${d.waterGoalNote}'
                  : '${d.waterMl} / ${d.waterGoalMl} ml · ${d.waterGoalNote}',
              progress: d.waterGoalMl == null ? null : d.waterProgress,
              progressLabel: 'Water progress',
              trailing: AppIconButton(
                icon: LucideIcons.plus,
                label: 'Add $kWaterStepMl ml',
                onCard: true,
                onPressed: () => _addWater(context, ref),
              ),
            ),
            const SizedBox(height: AppSpace.cardGap),
            _HabitCard(
              icon: LucideIcons.activity,
              title: 'Steps',
              subtitle:
                  '${formatThousands(d.steps)} / ${formatThousands(d.stepGoal)}'
                  ' · ${d.stepGoalNote}',
              trailing: AppIconButton(
                icon: LucideIcons.plus,
                label: 'Log steps',
                onCard: true,
                onPressed: () => _logSteps(context, ref),
              ),
              progress: d.stepGoal > 0 ? d.stepProgress : null,
              progressLabel: 'Step progress',
            ),
            const SizedBox(height: AppSpace.cardGap),
            _HabitCard(
              icon: LucideIcons.heart,
              title: 'Exercise',
              subtitle: d.exerciseLabel ?? 'Not logged yet',
              trailing: d.exerciseLabel == null
                  ? GhostButton(
                      label: 'Log walk',
                      compact: true,
                      onPressed: () => _logWalk(context, ref),
                    )
                  : StatusLabel(
                      status: ValueStatus.ok,
                      text: d.exerciseMinutes > 0
                          ? 'Logged · ${d.exerciseMinutes} min'
                          : 'Logged',
                    ),
            ),
            const SizedBox(height: AppSpace.cardGap),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CardTag(
                    icon: LucideIcons.lightbulb,
                    label: 'Today’s tip',
                  ),
                  Text(
                    d.dailyTip,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogStepsDialog extends StatefulWidget {
  const _LogStepsDialog();

  @override
  State<_LogStepsDialog> createState() => _LogStepsDialogState();
}

class _LogStepsDialogState extends State<_LogStepsDialog> {
  final TextEditingController _input = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Log steps'),
    content: TextField(
      controller: _input,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Steps to add',
        hintText: 'For example, 1200',
        errorText: _validationError,
      ),
    ),
    actions: [
      GhostButton(
        label: 'Cancel',
        compact: true,
        onPressed: () => Navigator.pop(context),
      ),
      PrimaryButton(
        label: 'Log steps',
        compact: true,
        onPressed: () {
          final int? value = int.tryParse(_input.text.trim());
          if (value == null || value < 1 || value > 50000) {
            setState(
              () => _validationError = 'Enter a number from 1 to 50,000.',
            );
            return;
          }
          Navigator.pop(context, value);
        },
      ),
    ],
  );
}

/// Mockup habit card: icon tile, bold title, muted small subtitle, optional
/// trailing control, optional progress bar 12 px below.
class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.progress,
    this.progressLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final double? progress;
  final String? progressLabel;

  /// Above this text scale the trailing control moves under the text so a
  /// wide "Log walk" never squeezes the title at 320 dp.
  static const double _stackScale = 1.4;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool stack =
        trailing != null &&
        MediaQuery.textScalerOf(context).scale(AppType.bodySize) >
            AppType.bodySize * _stackScale;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: icon),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              if (trailing != null && !stack) ...[
                const SizedBox(width: AppSpace.lg),
                trailing!,
              ],
            ],
          ),
          if (stack) ...[
            const SizedBox(height: AppSpace.cardGap),
            Align(alignment: Alignment.centerRight, child: trailing),
          ],
          if (progress != null) ...[
            const SizedBox(height: AppSpace.cardGap),
            ProgressBar(value: progress!, semanticLabel: progressLabel),
          ],
        ],
      ),
    );
  }
}

/// 4120 → "4,120". No locale package in the approved list, so a plain
/// comma separator as in the mockup.
String formatThousands(int n) {
  final String digits = n.abs().toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return n < 0 ? '-$out' : out.toString();
}
