/// Design-system guards (docs/design-system.md §7): the palette matches
/// the mockup exactly, text/background pairs clear WCAG AA in both themes,
/// interactive components meet the 48 dp hit target, and `lib/` contains no
/// blur, shadow, gradient or hex-literal escape hatches.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/theme/ai_surface.dart';
import 'package:tahasync_medaix/theme/app_theme.dart';

import 'support/test_app.dart';

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double light = la > lb ? la : lb;
  final double dark = la > lb ? lb : la;
  return (light + 0.05) / (dark + 0.05);
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

void main() {
  group('palette drift guard', () {
    const Map<String, String> dark = <String, String>{
      'background': '#0E1726',
      'surface': '#1E293B',
      'surface2': '#273449',
      'surfaceModal': '#334155',
      'primary': '#A8B0D5',
      'onPrimary': '#0E1726',
      'text': '#F1F5F9',
      'muted': '#A3B1C6',
      'ai': '#BDA7FF',
      'aiFill': '#9333EA',
      'onAiFill': '#FFFFFF',
      'ok': '#34D399',
      'warn': '#FBBF24',
      'error': '#F87171',
      'hairline': '#334155',
      'outlineStrong': '#8A99AE',
    };
    const Map<String, String> light = <String, String>{
      'background': '#F8FAFC',
      'surface': '#FFFFFF',
      'surface2': '#E8EDF4',
      'surfaceModal': '#FFFFFF',
      'primary': '#182346',
      'onPrimary': '#FFFFFF',
      'text': '#0F172A',
      'muted': '#475569',
      'ai': '#6D45E8',
      'aiFill': '#6D45E8',
      'onAiFill': '#FFFFFF',
      'ok': '#047857',
      'warn': '#92400E',
      'error': '#B91C1C',
      'hairline': '#E2E8F0',
      'outlineStrong': '#64748B',
    };

    Map<String, Color> tokens(AppColors c) => <String, Color>{
      'background': c.background,
      'surface': c.surface,
      'surface2': c.surface2,
      'surfaceModal': c.surfaceModal,
      'primary': c.primary,
      'onPrimary': c.onPrimary,
      'text': c.text,
      'muted': c.muted,
      'ok': c.ok,
      'warn': c.warn,
      'error': c.error,
      'hairline': c.hairline,
      'outlineStrong': c.outlineStrong,
      'ai': c.ai,
      'aiFill': c.aiFill,
      'onAiFill': c.onAiFill,
    };

    test('dark tokens match docs/design-system.md §2', () {
      final Map<String, Color> t = tokens(AppColors.dark);
      for (final entry in dark.entries) {
        expect(_hex(t[entry.key]!), entry.value, reason: entry.key);
      }
    });

    test('light tokens match docs/design-system.md §2', () {
      final Map<String, Color> t = tokens(AppColors.light);
      for (final entry in light.entries) {
        expect(_hex(t[entry.key]!), entry.value, reason: entry.key);
      }
    });

    test('brand palette is the locked five', () {
      expect(_hex(Brand.ink), '#0E0D15');
      expect(_hex(Brand.navy), '#182346');
      expect(_hex(Brand.steel), '#3D5387');
      expect(_hex(Brand.slate), '#7C83AD');
      expect(_hex(Brand.mauve), '#BFA9BA');
    });
  });

  group('contrast', () {
    for (final (String name, AppColors c) in <(String, AppColors)>[
      ('dark', AppColors.dark),
      ('light', AppColors.light),
    ]) {
      test('$name theme text pairs are ≥ 4.5:1', () {
        final List<(String, Color, Color)> pairs = <(String, Color, Color)>[
          ('text on background', c.text, c.background),
          ('text on surface', c.text, c.surface),
          ('text on surface2', c.text, c.surface2),
          ('muted on background', c.muted, c.background),
          ('muted on surface', c.muted, c.surface),
          ('muted on surface2', c.muted, c.surface2),
          ('onPrimary on primary', c.onPrimary, c.primary),
          ('ok on surface', c.ok, c.surface),
          ('warn on surface', c.warn, c.surface),
          ('error on surface', c.error, c.surface),
          ('toast: background on text', c.background, c.text),
          ('primary on background', c.primary, c.background),
        ];
        for (final (label, fg, bg) in pairs) {
          final double ratio = _contrast(fg, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$label is ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });

      // Status colours on surface2 only ever back an icon next to text in
      // `text` colour (StatusLabel), so they are held to the 3:1 graphics
      // threshold. Status text is never set directly on surface2.
      test('$name theme status icons on surface2 are ≥ 3:1', () {
        for (final (label, fg) in <(String, Color)>[
          ('ok', c.ok),
          ('warn', c.warn),
          ('error', c.error),
        ]) {
          final double ratio = _contrast(fg, c.surface2);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason: '$label on surface2 is ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });
    }

    test('all text roles clear each surface layer', () {
      for (final AppColors c in <AppColors>[AppColors.light, AppColors.dark]) {
        final surfaces = <Color>[
          c.background,
          c.surface,
          c.surface2,
          c.surfaceModal,
        ];
        final textRoles = <Color>[c.text, c.muted, c.ai, c.primary];
        for (int role = 0; role < textRoles.length; role++) {
          for (int surface = 0; surface < surfaces.length; surface++) {
            expect(
              _contrast(textRoles[role], surfaces[surface]),
              greaterThanOrEqualTo(4.5),
            );
          }
        }
        for (final Color statusColor in <Color>[c.ok, c.warn, c.error]) {
          for (final Color surface in surfaces) {
            expect(_contrast(statusColor, surface), greaterThanOrEqualTo(3));
          }
        }
        expect(_contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.onAiFill, c.aiFill), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.outlineStrong, c.surface), greaterThanOrEqualTo(3));
        expect(_contrast(c.ai, c.surface), greaterThanOrEqualTo(3));
      }
    });
  });

  group('hit targets', () {
    Future<Size> sizeOf(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        testScreen(
          Scaffold(
            body: Center(child: UnconstrainedBox(child: child)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byWidget(child));
    }

    testWidgets('buttons and icon buttons are at least 48 dp tall', (
      tester,
    ) async {
      final List<Widget> targets = <Widget>[
        PrimaryButton(label: 'Try again', onPressed: () {}, expanded: false),
        GhostButton(label: 'Skip for now', onPressed: () {}, expanded: false),
        LinkButton(label: 'Remind me later', onPressed: () {}),
        AppIconButton(
          icon: LucideIcons.bell,
          label: 'Reminders',
          onPressed: () {},
        ),
        AppSwitch(value: true, onChanged: (_) {}, label: 'Dark appearance'),
      ];
      for (final Widget w in targets) {
        final Size size = await sizeOf(tester, w);
        expect(
          size.height,
          greaterThanOrEqualTo(AppSize.button),
          reason: '${w.runtimeType} height ${size.height}',
        );
        expect(
          size.width,
          greaterThanOrEqualTo(AppSize.button),
          reason: '${w.runtimeType} width ${size.width}',
        );
      }
    });

    testWidgets('chips are 34 dp, or 44 dp as a main control', (tester) async {
      final Size small = await sizeOf(
        tester,
        AppChip(label: 'Diabetes', onTap: () {}),
      );
      expect(small.height, greaterThanOrEqualTo(AppSize.chip));
      final Size large = await sizeOf(
        tester,
        AppChip(label: '30 min', large: true, onTap: () {}),
      );
      expect(large.height, greaterThanOrEqualTo(AppSize.chipLarge));
    });

    testWidgets(
      'nav slots are full-height hit targets with a 64 × 32 indicator',
      (tester) async {
        await tester.pumpWidget(
          testScreen(
            Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: FloatingNav(
                  items: const <NavItem>[
                    NavItem(icon: LucideIcons.home, label: 'Home'),
                    NavItem(icon: LucideIcons.fileText, label: 'Reports'),
                  ],
                  selectedIndex: 0,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final Size slot = tester.getSize(
          find.ancestor(of: find.text('Home'), matching: find.byType(InkWell)),
        );
        expect(slot.height, AppSize.navHeight);
        expect(slot.width, greaterThanOrEqualTo(AppSize.navItemWidth));
        final Size indicator = tester.getSize(
          find.descendant(
            of: find.ancestor(
              of: find.text('Home'),
              matching: find.byType(InkWell),
            ),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(indicator.width, AppSize.navIndicatorWidth);
        expect(indicator.height, AppSize.navIndicatorHeight);
      },
    );

    testWidgets('five nav slots fit a 320 dp screen at 200 % text', (
      tester,
    ) async {
      await usePhone(tester, size: const Size(320, 640));
      await tester.pumpWidget(
        testScreen(
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: FloatingNav(
                items: const <NavItem>[
                  NavItem(icon: LucideIcons.home, label: 'Home'),
                  NavItem(icon: LucideIcons.fileText, label: 'Reports'),
                  NavItem(icon: LucideIcons.pill, label: 'Meds'),
                  NavItem(icon: LucideIcons.heart, label: 'Wellness'),
                  NavItem(icon: LucideIcons.menu, label: 'More'),
                ],
                selectedIndex: 3,
                onSelected: (_) {},
              ),
            ),
          ),
          size: const Size(320, 640),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final Finder slot = find.ancestor(
        of: find.text('Wellness'),
        matching: find.byType(InkWell),
      );
      // 320 − 2·14 inset − 2·6 padding = 280 → 56 per slot, as in the mockup.
      expect(tester.getSize(slot).width, AppSize.navItemWidth);
      final Size indicator = tester.getSize(
        find.descendant(of: slot, matching: find.byType(AnimatedContainer)),
      );
      expect(
        indicator.width,
        AppSize.navItemWidth - 2 * AppSize.navIndicatorGap,
      );
    });

    testWidgets('nav uses surface2 and a flat hairline in dark mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        testScreen(
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: FloatingNav(
                items: const <NavItem>[
                  NavItem(icon: LucideIcons.home, label: 'Home'),
                  NavItem(icon: LucideIcons.fileText, label: 'Reports'),
                  NavItem(icon: LucideIcons.heart, label: 'Wellness'),
                  NavItem(icon: LucideIcons.menu, label: 'More'),
                ],
                selectedIndex: 0,
                onSelected: (_) {},
              ),
            ),
          ),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Home'));
      final colors = Theme.of(context).extension<AppColors>()!;
      final nav = tester.widget<Container>(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration! as BoxDecoration).color ==
                      colors.surface2,
            )
            .first,
      );
      final decoration = nav.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isEmpty);
      expect(decoration.border!.top.width, 1);
      expect(decoration.border!.top.color, colors.hairline);
    });

    testWidgets('light nav keeps the surface2 shadow treatment', (
      tester,
    ) async {
      await tester.pumpWidget(
        testScreen(
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: FloatingNav(
                items: const <NavItem>[
                  NavItem(icon: LucideIcons.home, label: 'Home'),
                  NavItem(icon: LucideIcons.fileText, label: 'Reports'),
                  NavItem(icon: LucideIcons.heart, label: 'Wellness'),
                  NavItem(icon: LucideIcons.menu, label: 'More'),
                ],
                selectedIndex: 0,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final colors = Theme.of(
        tester.element(find.text('Home')),
      ).extension<AppColors>()!;
      final nav = tester.widget<Container>(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration! as BoxDecoration).color ==
                      colors.surface2,
            )
            .first,
      );
      final decoration = nav.decoration! as BoxDecoration;
      expect(decoration.boxShadow, AppShadow.nav);
      expect(decoration.border, isNull);
    });
  });

  testWidgets('upload progress fill grows from the leading edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      testScreen(
        const Scaffold(
          body: Center(
            child: SizedBox(width: 200, child: ProgressBar(value: 0.25)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder bar = find.byType(ProgressBar);
    final Rect track = tester.getRect(
      find.descendant(of: bar, matching: find.byType(ClipRRect)),
    );
    final Rect fill = tester.getRect(
      find.descendant(of: bar, matching: find.byType(AnimatedContainer)),
    );
    expect(fill.left, closeTo(track.left, 0.1));
    expect(fill.width, closeTo(track.width * 0.25, 0.1));
  });

  testWidgets('AI busy action glows only in dark mode while busy', (
    tester,
  ) async {
    for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(
        testScreen(
          const AiBusyAction(
            busy: true,
            child: SizedBox(width: 120, height: 48),
          ),
          themeMode: mode,
        ),
      );
      await tester.pumpAndSettle();
      final DecoratedBox box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(AiBusyAction),
          matching: find.byType(DecoratedBox),
        ),
      );
      final shadows = (box.decoration as BoxDecoration).boxShadow;
      expect(shadows, mode == ThemeMode.dark ? hasLength(1) : isEmpty);
    }
  });

  group('source integrity', () {
    final Directory lib = Directory('lib');
    final List<File> files = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    String rel(File f) => f.path.replaceAll('\\', '/');

    test('no BackdropFilter or blur anywhere in lib/', () {
      for (final File f in files) {
        final String src = f.readAsStringSync();
        expect(src, isNot(contains('BackdropFilter')), reason: rel(f));
        expect(src, isNot(contains('ImageFilter.blur')), reason: rel(f));
      }
    });

    test('shadows stay in tokens and the AI surface file', () {
      for (final File f in files) {
        if (rel(f).endsWith('theme/app_tokens.dart') ||
            rel(f).endsWith('theme/ai_surface.dart')) {
          continue;
        }
        expect(
          f.readAsStringSync(),
          isNot(contains('BoxShadow(')),
          reason: rel(f),
        );
      }
    });

    test('no gradients outside the skeleton shimmer', () {
      for (final File f in files) {
        if (rel(f).endsWith('core/widgets/feedback_loading.dart')) continue;
        final String src = f.readAsStringSync();
        expect(src, isNot(contains('LinearGradient(')), reason: rel(f));
        expect(src, isNot(contains('RadialGradient(')), reason: rel(f));
        expect(src, isNot(contains('SweepGradient(')), reason: rel(f));
      }
    });

    test('native splash and icon generator stay flat', () {
      final File generator = File('../tool/generate_icons.py');
      expect(generator.existsSync(), isTrue, reason: 'run tests from app/');
      final String gen = generator.readAsStringSync();
      expect(gen, isNot(contains('GRADIENT')));
      expect(gen, isNot(contains('sample_gradient')));
      expect(gen, isNot(contains('LinearGradient')));
      expect(gen, isNot(contains('add_specular')));
      expect(gen, contains('#182346'));
      expect(gen, contains('#0E0D15'));
      expect(gen, contains('#F7F4F2'));

      for (final String path in <String>[
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
        'android/app/src/main/res/values/colors.xml',
        'android/app/src/main/res/values-night/colors.xml',
      ]) {
        final String src = File(path).readAsStringSync();
        // Strip XML comments before checking to avoid false positives
        final String srcNoComments = src.replaceAll(
          RegExp(r'<!--.*?-->', dotAll: true),
          '',
        );
        expect(
          srcNoComments.toLowerCase(),
          isNot(contains('gradient')),
          reason: path,
        );
      }
      expect(
        File('android/app/src/main/res/values/colors.xml').readAsStringSync(),
        contains('#F7F4F2'),
      );
      expect(
        File(
          'android/app/src/main/res/values-night/colors.xml',
        ).readAsStringSync(),
        contains('#0E0D15'),
      );
    });

    test('no hex colour literals outside the theme token files', () {
      final RegExp hex = RegExp(r'Color\(0x[0-9A-Fa-f]{6,8}\)');
      for (final File f in files) {
        if (rel(f).endsWith('theme/app_colors.dart') ||
            rel(f).endsWith('theme/app_tokens.dart')) {
          continue;
        }
        expect(
          hex.hasMatch(f.readAsStringSync()),
          isFalse,
          reason: '${rel(f)} contains a hex colour literal',
        );
      }
    });

    test('no Colors.<name> swatches outside the theme', () {
      final RegExp swatch = RegExp(r'Colors\.(?!transparent)[a-z]+');
      for (final File f in files) {
        if (rel(f).contains('/theme/')) continue;
        expect(
          swatch.hasMatch(f.readAsStringSync()),
          isFalse,
          reason: '${rel(f)} uses a Material swatch instead of a token',
        );
      }
    });
  });
}
