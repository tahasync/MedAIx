/// Scan medicine (mockup `scan`): explain the camera first, then the
/// viewfinder with its sweep line, then the matched packet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../data/meds_repository.dart';
import '../providers/meds_providers.dart';

class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  /// Fallback for people who would rather not use the camera: back to
  /// Meds with the add sheet open.
  void _typeInstead(BuildContext context, WidgetRef ref) {
    ref.read(medsAddSheetRequestProvider.notifier).request();
    context.go(AppRoutes.meds);
  }

  Future<void> _addMatched(BuildContext context, WidgetRef ref) async {
    final bool ok = await ref.read(scanProvider.notifier).addMatched();
    if (!context.mounted) return;
    if (ok) {
      showToast(context, 'Medicine added');
      context.go(AppRoutes.meds);
    } else {
      showToast(context, 'Couldn’t add that medicine. Your list is unchanged.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ScanState scan = ref.watch(scanProvider);
    final ScanController controller = ref.read(scanProvider.notifier);
    final bool permission = scan.step == ScanStep.permission;

    return AppScaffold(
      body: AppScreen(
        header: ScreenHeader(
          title: 'Scan medicine',
          subtitle: permission ? null : 'Point at the packet',
        ),
        children: switch (scan.step) {
          ScanStep.permission => [
            _PermissionCard(
              onAllow: controller.allowCamera,
              onTypeInstead: () => _typeInstead(context, ref),
            ),
          ],
          ScanStep.scanning => [
            const _Viewfinder(),
            const SizedBox(height: AppSpace.cardGap),
            PrimaryButton(
              label: 'Capture packet',
              icon: LucideIcons.camera,
              loading: scan.busy,
              onPressed: controller.capture,
            ),
          ],
          ScanStep.failed => [
            const _Viewfinder(),
            const SizedBox(height: AppSpace.cardGap),
            ErrorCard(
              title: 'Couldn’t read the packet',
              message:
                  scan.errorMessage ??
                  'The packet was too blurry to read the name.',
              dataSafety: 'Nothing was added to your list.',
              onPrimary: controller.retry,
              secondaryLabel: 'Type the name instead',
              onSecondary: () => _typeInstead(context, ref),
            ),
          ],
          ScanStep.matched => [
            _Viewfinder(result: scan.result),
            const SizedBox(height: AppSpace.cardGap),
            _MatchCard(
              result: scan.result!,
              adding: scan.busy,
              onAdd: () => _addMatched(context, ref),
            ),
          ],
        },
      ),
    );
  }
}

/// Permission step: explain before asking, and offer a way around it.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onAllow, required this.onTypeInstead});

  final VoidCallback onAllow;
  final VoidCallback onTypeInstead;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(icon: LucideIcons.camera),
          const SizedBox(height: AppSpace.sectionBottom),
          Semantics(
            header: true,
            child: Text('Camera access needed', style: text.titleLarge),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'We use the camera only to read the name on the packet. '
            'Photos aren’t stored.',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
          const SizedBox(height: AppSpace.cardGap),
          PrimaryButton(
            label: 'Allow camera',
            icon: LucideIcons.camera,
            onPressed: onAllow,
          ),
          const SizedBox(height: AppSpace.cardGap),
          GhostButton(
            label: 'Type the name instead',
            icon: LucideIcons.keyboard,
            onPressed: onTypeInstead,
          ),
        ],
      ),
    );
  }
}

/// Mockup `.view`: 300 high dark viewfinder, radius 26. While scanning it
/// shows the frame with a sweep line (static under reduced motion); once
/// matched, a check mark and the name read from the packet.
class _Viewfinder extends StatefulWidget {
  const _Viewfinder({this.result});

  final ScanResult? result;

  @override
  State<_Viewfinder> createState() => _ViewfinderState();
}

class _ViewfinderState extends State<_Viewfinder>
    with SingleTickerProviderStateMixin {
  static const Duration _sweepDuration = Duration(seconds: 2);
  static const double _frameInsetY = 50;
  static const double _frameInsetX = 44;
  static const double _lineInset = 8;

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: _sweepDuration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Viewfinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final bool animate = widget.result == null && !AppMotion.reduced(context);
    if (animate) {
      if (!_sweep.isAnimating) _sweep.repeat(reverse: true);
    } else {
      _sweep.stop();
      _sweep.value = 0;
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final ScanResult? result = widget.result;

    final Widget content = result != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.check, size: 44, color: c.onViewfinder),
                const SizedBox(height: AppSpace.md),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.card,
                  ),
                  child: Text(
                    result.readName,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: c.onViewfinder),
                  ),
                ),
              ],
            ),
          )
        : Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: _frameInsetY,
                    horizontal: _frameInsetX,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: c.scanFrame, width: 2),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppRadius.tile),
                      ),
                    ),
                    child: AnimatedBuilder(
                      animation: _sweep,
                      builder: (context, _) => Align(
                        alignment: Alignment(0, -1 + 2 * _sweep.value),
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(
                            horizontal: _lineInset,
                          ),
                          color: c.scanFrame,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  'Hold steady…',
                  style: text.bodySmall?.copyWith(color: c.onViewfinder),
                ),
              ),
            ],
          );

    return Semantics(
      container: true,
      label: result == null
          ? 'Camera viewfinder. Hold steady while we read the packet.'
          : 'Packet read: ${result.readName}',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: AppRadius.viewfinderAll,
        child: Container(
          height: AppSize.viewfinder,
          color: c.viewfinder,
          child: content,
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.result,
    required this.adding,
    required this.onAdd,
  });

  final ScanResult result;
  final bool adding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return FadeIn(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (result.safeWithCurrent)
              CardTag(
                icon: LucideIcons.check,
                label: 'Matches your list',
                color: c.ok,
              )
            else
              CardTag(
                icon: LucideIcons.alertTriangle,
                label: 'May clash with your list',
                color: c.warn,
              ),
            Text(
              '${result.genericName}. ${result.note}',
              style: text.bodyMedium?.copyWith(color: c.muted),
            ),
            const SizedBox(height: AppSpace.cardGap),
            PrimaryButton(
              label: 'Add to my medicines',
              loading: adding,
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}
