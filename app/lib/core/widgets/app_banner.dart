/// A shared, prioritized status banner for connectivity, sync, updates and
/// one-off information.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';

enum AppBannerKind { offline, retrying, update, info }

@immutable
class AppBannerMessage {
  const AppBannerMessage({
    required this.kind,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final AppBannerKind kind;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// Owns at most one message of each kind. [current] always returns the
/// highest-priority active message.
class AppBannerController extends Notifier<List<AppBannerMessage>> {
  bool _deviceOffline = false;
  bool _requestOffline = false;
  bool _outboxOffline = false;
  bool _requestRetrying = false;
  bool _outboxSyncing = false;
  bool _updateDismissed = false;

  @override
  List<AppBannerMessage> build() => const [];

  AppBannerMessage? get current {
    if (state.isEmpty) return null;
    return state.reduce((a, b) => a.kind.index <= b.kind.index ? a : b);
  }

  void setDeviceOffline(bool offline) {
    _deviceOffline = offline;
    _syncOfflineMessage();
  }

  void setRequestOffline(bool offline) {
    _requestOffline = offline;
    _syncOfflineMessage();
  }

  void setOutboxOffline(bool offline) {
    _outboxOffline = offline;
    _syncOfflineMessage();
  }

  void _syncOfflineMessage() {
    final index = state.indexWhere(
      (item) => item.kind == AppBannerKind.offline,
    );
    final next = [...state];
    if (_deviceOffline || _requestOffline || _outboxOffline) {
      const offline = AppBannerMessage(
        kind: AppBannerKind.offline,
        message:
            'You’re offline. Changes are saved and sync when you reconnect.',
      );
      if (index < 0) {
        next.add(offline);
      } else {
        next[index] = offline;
      }
    } else if (index >= 0) {
      next.removeAt(index);
    }
    state = List.unmodifiable(next);
  }

  void setRetrying(bool retrying) {
    _requestRetrying = retrying;
    _syncRetryingMessage();
  }

  void setOutboxSyncing(bool syncing) {
    _outboxSyncing = syncing;
    _syncRetryingMessage();
  }

  void _syncRetryingMessage() {
    final syncing = _outboxSyncing || _requestRetrying;
    final message = _outboxSyncing
        ? 'Syncing saved entries…'
        : 'Reconnecting to MedAIx…';
    _put(
      AppBannerMessage(kind: AppBannerKind.retrying, message: message),
      enabled: syncing,
    );
  }

  void setUpdate({required String message, required VoidCallback onUpdate}) {
    if (_updateDismissed) return;
    _put(
      AppBannerMessage(
        kind: AppBannerKind.update,
        message: message,
        actionLabel: 'Update',
        onAction: onUpdate,
      ),
    );
  }

  void showInfo(String message, {String? actionLabel, VoidCallback? onAction}) {
    _put(
      AppBannerMessage(
        kind: AppBannerKind.info,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
  }

  void clear(AppBannerKind kind) {
    state = List.unmodifiable(state.where((item) => item.kind != kind));
  }

  void dismiss(AppBannerKind kind) {
    if (kind == AppBannerKind.offline) return;
    if (kind == AppBannerKind.update) _updateDismissed = true;
    clear(kind);
  }

  void _put(AppBannerMessage item, {bool enabled = true}) {
    final next = [...state.where((old) => old.kind != item.kind)];
    if (enabled) next.add(item);
    state = List.unmodifiable(next);
  }
}

final appBannerProvider =
    NotifierProvider<AppBannerController, List<AppBannerMessage>>(
      AppBannerController.new,
    );

/// Renders the highest-priority banner. Its live region announces changes to
/// assistive technology and the text always names the status.
class AppBanner extends ConsumerWidget {
  const AppBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(
      appBannerProvider.select(
        (_) => ref.read(appBannerProvider.notifier).current,
      ),
    );
    final c = context.colors;
    final duration = AppMotion.of(context, AppMotion.fast);
    final color = switch (item?.kind) {
      AppBannerKind.offline || AppBannerKind.retrying => c.warn,
      AppBannerKind.update || AppBannerKind.info => c.primary,
      null => c.primary,
    };
    final icon = switch (item?.kind) {
      AppBannerKind.offline => LucideIcons.wifiOff,
      AppBannerKind.retrying => LucideIcons.refreshCw,
      AppBannerKind.update => LucideIcons.download,
      AppBannerKind.info => LucideIcons.info,
      null => LucideIcons.info,
    };

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: item == null
          ? const SizedBox.shrink(key: ValueKey('empty'))
          : Semantics(
              key: ValueKey('${item.kind}:${item.message}'),
              liveRegion: true,
              container: true,
              label: item.message,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: AppRadius.bannerAll,
                ),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(icon, size: AppSize.iconSmall, color: color),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Text(
                        item.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (item.actionLabel != null && item.onAction != null)
                      TextButton(
                        onPressed: item.onAction,
                        child: Text(item.actionLabel!),
                      ),
                    if (item.kind != AppBannerKind.offline)
                      IconButton(
                        tooltip: 'Dismiss',
                        onPressed: () => ref
                            .read(appBannerProvider.notifier)
                            .dismiss(item.kind),
                        icon: const Icon(
                          LucideIcons.x,
                          size: AppSize.iconSmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
