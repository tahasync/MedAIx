import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'app_card.dart';
import 'buttons.dart';

enum SlowOperationStage { normal, waking, stillWaiting }

const Duration kSlowOperationWakingDelay = Duration(seconds: 8);
const Duration kSlowOperationRetryDelay = Duration(seconds: 25);

/// Timer for the shared normal → waking → still-waiting progression.
class SlowOperationTimer {
  SlowOperationTimer(this.onStage);

  final ValueChanged<SlowOperationStage> onStage;
  Timer? _timer;

  void start() {
    cancel();
    onStage(SlowOperationStage.normal);
    _timer = Timer(kSlowOperationWakingDelay, () {
      onStage(SlowOperationStage.waking);
      _timer = Timer(kSlowOperationRetryDelay - kSlowOperationWakingDelay, () {
        onStage(SlowOperationStage.stillWaiting);
        _timer = null;
      });
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// A wait explanation that leaves the operation's real-size skeleton visible.
class SlowOperationHint extends StatefulWidget {
  const SlowOperationHint({
    super.key,
    required this.pending,
    required this.onRetry,
    required this.child,
    this.body =
        'The server rests when it isn’t used, so the first request can take up to a minute. Your report is safe.',
  });

  final bool pending;
  final VoidCallback onRetry;
  final Widget child;
  final String body;

  @override
  State<SlowOperationHint> createState() => _SlowOperationHintState();
}

class _SlowOperationHintState extends State<SlowOperationHint> {
  late final SlowOperationTimer _tracker;
  SlowOperationStage _stage = SlowOperationStage.normal;

  @override
  void initState() {
    super.initState();
    _tracker = SlowOperationTimer((stage) {
      if (mounted && _stage != stage) setState(() => _stage = stage);
    });
    _updatePending(widget.pending);
  }

  @override
  void didUpdateWidget(covariant SlowOperationHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pending != widget.pending) _updatePending(widget.pending);
  }

  void _updatePending(bool pending) {
    _tracker.cancel();
    _stage = SlowOperationStage.normal;
    if (!pending) return;
    _tracker.start();
  }

  void _retry() {
    _tracker.start();
    widget.onRetry();
  }

  @override
  void dispose() {
    _tracker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      widget.child,
      if (_stage != SlowOperationStage.normal)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.cardGap),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Waking up MedAIx…',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    widget.body,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_stage == SlowOperationStage.stillWaiting) ...[
                    const SizedBox(height: AppSpace.md),
                    PrimaryButton(label: 'Try again', onPressed: _retry),
                  ],
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
