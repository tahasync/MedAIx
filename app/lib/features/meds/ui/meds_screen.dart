/// Medicine check (mockup `meds`): the list, the add sheet, "Check
/// interactions" and the warning / all-clear cards.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/features.dart';
import '../../../core/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../data/meds_repository.dart';
import '../providers/meds_providers.dart';

class MedsScreen extends ConsumerStatefulWidget {
  const MedsScreen({super.key});

  @override
  ConsumerState<MedsScreen> createState() => _MedsScreenState();
}

class _MedsScreenState extends ConsumerState<MedsScreen> {
  @override
  void initState() {
    super.initState();
    // A request made before this screen existed (deep link into the
    // scanner, then "Type the name instead").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(medsAddSheetRequestProvider)) _openAddSheet();
    });
  }

  Future<void> _openAddSheet() async {
    ref.read(medsAddSheetRequestProvider.notifier).consume();
    final int count = ref.read(medsProvider).valueOrNull?.length ?? 0;
    if (count >= kMaxMedicines) {
      showToast(context, 'You can track up to $kMaxMedicines medicines');
      return;
    }
    final bool? added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (_) => const _AddMedicineSheet(),
    );
    if (added == true && mounted) showToast(context, 'Medicine added');
  }

  Future<void> _remove(Medicine medicine) async {
    final bool ok = await ref.read(medsProvider.notifier).remove(medicine.id);
    if (!mounted) return;
    showToast(
      context,
      ok
          ? 'Removed ${medicine.name}'
          : 'Couldn’t remove ${medicine.name}. Your list is unchanged.',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(medsAddSheetRequestProvider, (_, bool next) {
      if (next) _openAddSheet();
    });
    final AsyncValue<List<Medicine>> meds = ref.watch(medsProvider);
    final AsyncValue<List<InteractionWarning>?> check = ref.watch(
      interactionCheckProvider,
    );

    return AppScaffold(
      body: AppScreen(
        header: const ScreenHeader(
          title: 'Medicine check',
          subtitle: 'Find risky combinations',
        ),
        onRefresh: () => ref.read(medsProvider.notifier).refresh(),
        children: meds.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const [
            SkeletonCard(height: 220),
            SizedBox(height: AppSpace.cardGap),
            SkeletonBox(height: AppSize.button, radius: AppRadius.button),
          ],
          error: (error, _) => [
            ErrorCard(
              title: 'Couldn’t load your medicines',
              message: friendlyError(
                error,
                'We couldn’t reach your medicines list.',
              ),
              dataSafety: 'Your medicines list is unchanged.',
              onPrimary: () => ref.read(medsProvider.notifier).refresh(),
            ),
          ],
          data: (items) => _content(context, items, check),
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    List<Medicine> items,
    AsyncValue<List<InteractionWarning>?> check,
  ) {
    final bool canAdd = items.length < kMaxMedicines;
    return [
      if (items.isEmpty)
        const EmptyState(
          icon: LucideIcons.pill,
          title: 'No medicines added',
          reason:
              'Add what you take. We’ll flag combinations that can cause harm.',
        )
      else
        AppCard(
          child: ListRows(
            rows: [
              for (final Medicine m in items)
                ListRow(
                  key: ValueKey<int>(m.id),
                  title: m.name,
                  titleBold: true,
                  leading: const IconTile(icon: LucideIcons.pill),
                  trailing: AppIconButton(
                    icon: LucideIcons.x,
                    label: 'Remove ${m.name}',
                    onCard: true,
                    onPressed: () => _remove(m),
                  ),
                ),
            ],
          ),
        ),
      const SizedBox(height: AppSpace.cardGap),
      GhostButton(
        icon: LucideIcons.plus,
        label: items.isEmpty ? 'Add first medicine' : 'Add another medicine',
        onPressed: canAdd ? _openAddSheet : null,
      ),
      if (items.length > 1) ...[
        const SizedBox(height: AppSpace.cardGap),
        PrimaryButton(
          label: 'Check interactions',
          loading: check.isLoading,
          onPressed: () => ref.read(interactionCheckProvider.notifier).run(),
        ),
      ],
      ...check.when(
        loading: () => const <Widget>[],
        error: (error, _) => [
          const SizedBox(height: AppSpace.cardGap),
          ErrorCard(
            title: 'Couldn’t check interactions',
            message: friendlyError(error, 'We couldn’t finish the check.'),
            dataSafety: 'Your medicines list is unchanged.',
            onPrimary: () => ref.read(interactionCheckProvider.notifier).run(),
          ),
        ],
        data: (warnings) => warnings == null || items.length < 2
            ? const <Widget>[]
            : _results(context, warnings),
      ),
    ];
  }

  List<Widget> _results(BuildContext context, List<InteractionWarning> w) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    if (w.isEmpty) {
      return [
        const SizedBox(height: AppSpace.cardGap),
        FadeIn(
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardTag(
                  icon: LucideIcons.check,
                  label: 'No risky combinations found',
                  color: c.ok,
                ),
                Text(
                  'Nothing here needs a doctor’s attention.',
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      for (final InteractionWarning warning in w) ...[
        const SizedBox(height: AppSpace.cardGap),
        FadeIn(
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardTag(
                  icon: LucideIcons.alertTriangle,
                  label: warning.title,
                  color: c.error,
                ),
                Text(warning.body, style: text.bodyMedium),
                if (ref.watch(featuresProvider).doctorMatch) ...[
                  const SizedBox(height: AppSpace.cardGap),
                  GhostButton(
                    label: 'Ask a doctor',
                    onPressed: () => context.go(AppRoutes.doctor),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ];
  }
}

/// Themed bottom sheet: suggestions as rows, or type a name and "Add".
class _AddMedicineSheet extends ConsumerStatefulWidget {
  const _AddMedicineSheet();

  @override
  ConsumerState<_AddMedicineSheet> createState() => _AddMedicineSheetState();
}

class _AddMedicineSheetState extends ConsumerState<_AddMedicineSheet> {
  final TextEditingController _name = TextEditingController();
  bool _adding = false;
  bool _failed = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add(String name) async {
    if (_adding || name.trim().isEmpty) return;
    setState(() {
      _adding = true;
      _failed = false;
    });
    final bool ok = await ref.read(medsProvider.notifier).add(name);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _adding = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<List<String>> suggestions = ref.watch(
      medSuggestionsProvider,
    );
    final bool canSubmit = !_adding && _name.text.trim().isNotEmpty;

    // Keyboard plus the gesture bar: the sheet's bottom edge is the screen's.
    final double bottom =
        MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screen,
          0,
          AppSpace.screen,
          AppSpace.screen,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Add a medicine', style: text.titleLarge),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Pick a common one or type the name on the packet.',
              style: text.bodySmall?.copyWith(color: c.muted),
            ),
            const SizedBox(height: AppSpace.lg),
            suggestions.when(
              loading: () => const Column(
                children: [
                  SkeletonBox(height: 56),
                  SizedBox(height: AppSpace.md),
                  SkeletonBox(height: 56),
                  SizedBox(height: AppSpace.md),
                  SkeletonBox(height: 56),
                ],
              ),
              error: (_, _) => Text(
                'Suggestions aren’t available right now. Type the name below.',
                style: text.bodySmall?.copyWith(color: c.muted),
              ),
              data: (names) => names.isEmpty
                  ? const SizedBox.shrink()
                  : ListRows(
                      rows: [
                        for (final String name in names)
                          ListRow(
                            title: name,
                            leading: const IconTile(icon: LucideIcons.pill),
                            trailing: ExcludeSemantics(
                              child: Icon(
                                LucideIcons.plus,
                                size: AppSize.icon,
                                color: c.text,
                              ),
                            ),
                            semanticLabel: 'Add $name',
                            onTap: _adding ? null : () => _add(name),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpace.lg),
            TextField(
              controller: _name,
              enabled: !_adding,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Type a medicine name',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: _add,
            ),
            if (_failed) ...[
              const SizedBox(height: AppSpace.md),
              CardTag(
                icon: LucideIcons.alertTriangle,
                label: 'Couldn’t add that medicine. Your list is unchanged.',
                color: c.error,
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            PrimaryButton(
              label: 'Add',
              loading: _adding,
              onPressed: canSubmit ? () => _add(_name.text) : null,
            ),
          ],
        ),
      ),
    );
  }
}
