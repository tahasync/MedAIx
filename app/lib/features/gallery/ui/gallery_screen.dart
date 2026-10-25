/// Visual regression reference for the design system: every kit component
/// rendered under the light and dark themes side by side (two columns when
/// wide, stacked when narrow). Reached from Settings in debug builds.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/brand/brand.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  static const List<_Section> _sections = <_Section>[
    _Section('Type and brand', _typeSection),
    _Section('Buttons', _buttonsSection),
    _Section('Chips and status', _chipsSection),
    _Section('Inputs', _inputsSection),
    _Section('Cards', _cardsSection),
    _Section('Tiles and rows', _tilesSection),
    _Section('Feedback', _feedbackSection),
    _Section('Empty and error states', _statesSection),
    _Section('Nav', _navSection),
  ];

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: AppScreen(
        insetForNav: false,
        showOfflineBanner: false,
        header: const ScreenHeader(
          title: 'Component gallery',
          subtitle: 'Every kit component, light and dark',
          showBack: true,
        ),
        children: [
          for (int i = 0; i < _sections.length; i++) ...[
            SectionTitle(_sections[i].title, first: i == 0),
            _ThemePair(builder: _sections[i].builder),
          ],
        ],
      ),
    );
  }
}

class _Section {
  const _Section(this.title, this.builder);

  final String title;
  final WidgetBuilder builder;
}

/// The same content under both themes. Side by side from 520 dp, stacked
/// below that (so 320 dp phones still fit).
class _ThemePair extends StatelessWidget {
  const _ThemePair({required this.builder});

  final WidgetBuilder builder;

  static const double _wide = 520;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Widget light = _ThemedPanel(
          theme: AppTheme.light,
          label: 'Light',
          builder: builder,
        );
        final Widget dark = _ThemedPanel(
          theme: AppTheme.dark,
          label: 'Dark',
          builder: builder,
        );
        if (constraints.maxWidth >= _wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: light),
              const SizedBox(width: AppSpace.cardGap),
              Expanded(child: dark),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            light,
            const SizedBox(height: AppSpace.cardGap),
            dark,
          ],
        );
      },
    );
  }
}

class _ThemedPanel extends StatelessWidget {
  const _ThemedPanel({
    required this.theme,
    required this.label,
    required this.builder,
  });

  final ThemeData theme;
  final String label;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final c = context.colors;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: c.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: c.muted),
                ),
                const SizedBox(height: AppSpace.md),
                builder(context),
              ],
            ),
          );
        },
      ),
    );
  }
}

Widget _gap([double height = AppSpace.lg]) => SizedBox(height: height);

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

Widget _typeSection(BuildContext context) {
  final c = context.colors;
  final TextTheme text = Theme.of(context).textTheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Row(
        children: [
          BrandMark(size: 36),
          SizedBox(width: AppSpace.lg),
          Flexible(child: BrandLockup(width: 120)),
        ],
      ),
      _gap(),
      Text('Headline 28', style: text.headlineMedium),
      Text('Title 19', style: text.titleLarge),
      Text('Section 16', style: text.titleMedium),
      Text('Body 15 explains a value in plain words.', style: text.bodyMedium),
      Text('Small 13 muted', style: text.bodySmall?.copyWith(color: c.muted)),
    ],
  );
}

Widget _buttonsSection(BuildContext context) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PrimaryButton(label: 'Primary', onPressed: () {}),
      _gap(AppSpace.md),
      PrimaryButton(
        label: 'Primary with icon',
        icon: LucideIcons.upload,
        onPressed: () {},
      ),
      _gap(AppSpace.md),
      PrimaryButton(label: 'Saving', loading: true, onPressed: () {}),
      _gap(AppSpace.md),
      const PrimaryButton(label: 'Disabled', onPressed: null),
      _gap(AppSpace.md),
      GhostButton(label: 'Ghost', icon: LucideIcons.camera, onPressed: () {}),
      _gap(AppSpace.md),
      Wrap(
        spacing: AppSpace.md,
        runSpacing: AppSpace.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PrimaryButton(label: 'Compact', compact: true, onPressed: () {}),
          GhostButton(label: 'Compact ghost', compact: true, onPressed: () {}),
          AppIconButton(
            icon: LucideIcons.bell,
            label: 'Reminders',
            onPressed: () {},
          ),
          AppCard(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: AppIconButton(
              icon: LucideIcons.plus,
              label: 'Add 250 ml',
              onCard: true,
              onPressed: () {},
            ),
          ),
        ],
      ),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          LinkButton(label: 'Link', onPressed: () {}),
          LinkButton(
            label: 'Destructive link',
            destructive: true,
            onPressed: () {},
          ),
        ],
      ),
    ],
  );
}

Widget _chipsSection(BuildContext context) {
  return StatefulBuilder(
    builder: (context, setState) {
      final Set<String> selected = _chipSelection;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpace.chipGap,
            runSpacing: AppSpace.chipGap,
            children: [
              for (final label in const ['Diabetes', 'Hypertension', 'Asthma'])
                AppChip(
                  label: label,
                  selected: selected.contains(label),
                  onTap: () => setState(() {
                    if (!selected.add(label)) selected.remove(label);
                  }),
                ),
              AppChip(label: 'Add', icon: LucideIcons.plus, onTap: () {}),
              const AppChip(label: 'Static'),
            ],
          ),
          _gap(),
          Row(
            children: [
              for (final minutes in const [15, 30, 60]) ...[
                Expanded(
                  child: AppChip(
                    label: '$minutes min',
                    large: true,
                    expand: true,
                    selected: minutes == 30,
                    onTap: () {},
                  ),
                ),
                if (minutes != 60) const SizedBox(width: AppSpace.md),
              ],
            ],
          ),
          _gap(),
          const Wrap(
            spacing: AppSpace.xl,
            runSpacing: AppSpace.md,
            children: [
              StatusLabel(status: ValueStatus.ok, text: 'All normal'),
              StatusLabel(status: ValueStatus.warn, text: 'Slightly high'),
              StatusLabel(status: ValueStatus.error, text: 'Risky together'),
              StatusLabel(status: ValueStatus.neutral, text: 'No range'),
            ],
          ),
          _gap(),
          const CardTag(icon: LucideIcons.sparkles, label: 'AI insight'),
          CardTag(
            icon: LucideIcons.triangleAlert,
            label: 'Rising 3 times in a row',
            color: context.colors.warn,
          ),
          CardTag(
            icon: LucideIcons.check,
            label: 'Matches your list',
            color: context.colors.ok,
          ),
        ],
      );
    },
  );
}

final Set<String> _chipSelection = <String>{'Diabetes'};

Widget _inputsSection(BuildContext context) {
  return const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        decoration: InputDecoration(
          labelText: 'Email',
          prefixIcon: Icon(LucideIcons.mail),
        ),
      ),
      SizedBox(height: AppSpace.lg),
      TextField(
        decoration: InputDecoration(
          labelText: 'Age',
          helperText: 'Used to set your goals',
        ),
      ),
      SizedBox(height: AppSpace.lg),
      TextField(
        decoration: InputDecoration(
          labelText: 'Password',
          prefixIcon: Icon(LucideIcons.lock),
          errorText: 'Use at least 6 characters for your password.',
        ),
      ),
      SizedBox(height: AppSpace.lg),
      TextField(
        enabled: false,
        decoration: InputDecoration(labelText: 'Disabled while saving'),
      ),
    ],
  );
}

Widget _cardsSection(BuildContext context) {
  final c = context.colors;
  final TextTheme text = Theme.of(context).textTheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardTag(icon: LucideIcons.sparkles, label: 'In plain words'),
            Text(
              'Your blood sugar average is slightly high. Cholesterol and '
              'kidney values look normal.',
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
      _gap(AppSpace.cardGap),
      AppCard(
        tone: CardTone.raised,
        child: Text('Raised card on surface2', style: text.bodyMedium),
      ),
      _gap(AppSpace.cardGap),
      AppCard(
        onTap: () {},
        semanticLabel: 'Tappable card',
        child: Row(
          children: [
            Expanded(child: Text('Tappable card', style: text.bodyMedium)),
            Icon(LucideIcons.chevronRight, size: AppSize.icon, color: c.text),
          ],
        ),
      ),
      _gap(AppSpace.cardGap),
      AiInsightCard(
        title: 'Your HbA1c has risen across 3 reports',
        body: '5.9 in March to 6.4 now. Worth raising with your doctor.',
        actionLabel: 'See the trend',
        onAction: () {},
      ),
      _gap(AppSpace.cardGap),
      SummaryRow(
        icon: const IconTile(icon: LucideIcons.fileText),
        title: 'Blood test, 18 Oct',
        subtitle: '2 values need attention',
        onTap: () {},
      ),
    ],
  );
}

Widget _tilesSection(BuildContext context) {
  return StatefulBuilder(
    builder: (context, setState) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              IconTile(icon: LucideIcons.fileText),
              SizedBox(width: AppSpace.md),
              IconTile(icon: LucideIcons.pill),
              SizedBox(width: AppSpace.md),
              IconTile(
                icon: LucideIcons.qrCode,
                size: AppSize.emptyIconTile,
                iconSize: AppSize.emptyIcon,
                radius: AppRadius.emptyIcon,
              ),
            ],
          ),
          _gap(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TileButton(
                  icon: LucideIcons.upload,
                  label: 'Upload report',
                  onTap: () {},
                ),
              ),
              const SizedBox(width: AppSpace.gridGap),
              Expanded(
                child: TileButton(
                  icon: LucideIcons.pill,
                  label: 'Check medicines',
                  onTap: () {},
                ),
              ),
            ],
          ),
          _gap(),
          AppCard(
            child: ListRows(
              rows: [
                ListRow(title: 'Reminders', onTap: () {}),
                ListRow(
                  title: 'Blood test',
                  subtitle: '18 Oct 2026',
                  leading: const IconTile(icon: LucideIcons.fileText),
                  trailing: const StatusLabel(
                    status: ValueStatus.warn,
                    text: '2 need attention',
                  ),
                  onTap: () {},
                ),
                ListRow(
                  title: 'Take medicines',
                  subtitle: 'Every day at 8:00 am',
                  titleBold: true,
                  trailing: AppSwitch(
                    value: _rowSwitch,
                    label: 'Take medicines',
                    onChanged: (on) => setState(() => _rowSwitch = on),
                  ),
                ),
                ListRow(
                  title: 'Age',
                  trailing: Text(
                    '28',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.colors.muted,
                    ),
                  ),
                ),
                ListRow(
                  title: 'Delete my data',
                  destructive: true,
                  trailing: const SizedBox.shrink(),
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

bool _rowSwitch = true;
bool _switchOn = true;

Widget _feedbackSection(BuildContext context) {
  return StatefulBuilder(
    builder: (context, setState) {
      final c = context.colors;
      final TextTheme text = Theme.of(context).textTheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProgressBar(value: 0.62, semanticLabel: 'Reading your report'),
          _gap(),
          const SkeletonBox(height: 56),
          _gap(AppSpace.md),
          const SkeletonCard(height: 88),
          _gap(),
          Row(
            children: [
              AppSwitch(
                value: _switchOn,
                label: 'Demo switch',
                onChanged: (on) => setState(() => _switchOn = on),
              ),
              const SizedBox(width: AppSpace.lg),
              const AppSwitch(
                value: false,
                label: 'Disabled switch',
                onChanged: null,
              ),
              const SizedBox(width: AppSpace.lg),
              const ScoreRing(value: 0.72, semanticLabel: 'Habit score 72'),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: Text(
                  'Habit score 72',
                  style: text.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          _gap(),
          const QrCard(
            seed: 42,
            semanticLabel: 'QR code, valid for one doctor visit',
            size: 140,
          ),
          _gap(),
          const OfflineBanner(),
          GhostButton(
            label: 'Show toast',
            onPressed: () => showToast(context, 'Details saved'),
          ),
          _gap(AppSpace.md),
          Text(
            'Toast: text-coloured plate above the nav, 1.8 s.',
            style: text.bodySmall?.copyWith(color: c.muted),
          ),
        ],
      );
    },
  );
}

Widget _statesSection(BuildContext context) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      EmptyState(
        icon: LucideIcons.fileText,
        title: 'No reports yet',
        reason:
            'Add a lab report and we’ll explain every value in plain '
            'language.',
        action: PrimaryButton(
          label: 'Scan a report',
          icon: LucideIcons.camera,
          onPressed: () {},
        ),
        secondaryAction: GhostButton(
          label: 'Choose from gallery or files',
          icon: LucideIcons.upload,
          onPressed: () {},
        ),
      ),
      _gap(AppSpace.cardGap),
      ErrorCard(
        title: 'Couldn’t read this photo',
        message: 'The image was too blurry to find any values.',
        dataSafety: 'Nothing was saved, and your existing reports are safe.',
        onPrimary: () {},
        secondaryLabel: 'Choose another file',
        onSecondary: () {},
      ),
    ],
  );
}

const List<NavItem> _navItems = <NavItem>[
  NavItem(icon: LucideIcons.home, label: 'Home'),
  NavItem(icon: LucideIcons.fileText, label: 'Reports'),
  NavItem(icon: LucideIcons.pill, label: 'Meds'),
  NavItem(icon: LucideIcons.heart, label: 'Wellness'),
  NavItem(icon: LucideIcons.menu, label: 'More'),
];

Widget _navSection(BuildContext context) {
  return StatefulBuilder(
    builder: (context, setState) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 362,
        child: FloatingNav(
          items: _navItems,
          selectedIndex: _navIndex,
          onSelected: (i) => setState(() => _navIndex = i),
        ),
      ),
    ),
  );
}

int _navIndex = 0;
