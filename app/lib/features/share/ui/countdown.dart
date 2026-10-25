/// A ticking mm:ss countdown shared by the Share screen and the doctor
/// portal. Reads [clockProvider] so tests can drive it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/share_repository.dart';
import '../providers/share_providers.dart';

/// Builds [builder] with the remaining time as `mm:ss`, re-rendering every
/// second until [expiresAt], then calls [onExpired] once.
///
/// Screen readers get [spokenLabel] through a live region; it is phrased
/// at minute granularity so the announcement changes roughly once a minute
/// rather than every second.
class CountdownText extends ConsumerStatefulWidget {
  const CountdownText({
    super.key,
    required this.expiresAt,
    required this.builder,
    required this.spokenLabel,
    this.onExpired,
  });

  final DateTime expiresAt;
  final Widget Function(BuildContext context, String countdown) builder;
  final String Function(Duration remaining) spokenLabel;
  final VoidCallback? onExpired;

  @override
  ConsumerState<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends ConsumerState<CountdownText> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _remaining = _compute();
    _start();
  }

  @override
  void didUpdateWidget(covariant CountdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt) {
      _remaining = _compute();
      _start();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration _compute() {
    final DateTime now = ref.read(clockProvider)();
    final Duration left = widget.expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  void _start() {
    _timer?.cancel();
    _timer = null;
    if (_remaining == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExpired?.call();
      });
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final Duration left = _compute();
    setState(() => _remaining = left);
    if (left == Duration.zero) {
      _timer?.cancel();
      _timer = null;
      widget.onExpired?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: widget.spokenLabel(_remaining),
      excludeSemantics: true,
      child: widget.builder(context, formatCountdown(_remaining)),
    );
  }
}

/// "29 minutes", "1 minute", "under a minute" — for spoken countdowns.
String describeRemaining(Duration remaining) {
  final int minutes = remaining.inMinutes;
  if (minutes <= 0) return 'under a minute';
  if (minutes == 1) return '1 minute';
  return '$minutes minutes';
}
