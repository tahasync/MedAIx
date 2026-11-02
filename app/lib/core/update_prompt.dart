/// In-app "Update Available" prompt, fed by the latest GitHub release.
///
/// Ported from foam-shop-pos's `update_checker.dart` and adapted to MedAIx:
///
///  * MedAIx release tags are sprint labels (`sprint-2-wk-03-04`), not
///    semver, so the remote version is read from the APK asset that
///    `.github/workflows/app-build.yml` attaches to every release
///    (`MedAIx-<tag>-v<major.minor.patch>-<build>-release.apk`). A `vX.Y.Z`
///    tag is the fallback; a release with neither is treated as no update.
///  * Versions carry the build number, so a rebuild at the same pubspec
///    version (`0.1.1+3` over `0.1.1+2`) still counts as newer.
///  * "Update Now" opens the APK's `browser_download_url` directly so the
///    phone downloads the file, falling back to the release page.
///  * The GitHub call goes through an injectable [http.Client], and the
///    Riverpod providers below are what the home screen listens to, so widget
///    tests swap them out and never touch the network.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import 'update_checker_service.dart';
import 'widgets/widgets.dart';

class UpdatePromptController extends Notifier<bool> {
  @override
  bool build() => false;

  void markShown() => state = true;
}

final updatePromptShownProvider =
    NotifierProvider<UpdatePromptController, bool>(UpdatePromptController.new);

/// Call from the home screen's `build`: starts the release check and shows
/// [showUpdateDialog] once per session when there is something newer.
///
/// Kept here so the home screen's own edit is a single line. The dialog is
/// deferred to the next frame so it never opens from inside a build.
void listenForAppUpdates(BuildContext context, WidgetRef ref) {
  ref.listen<AsyncValue<UpdateInfo?>>(latestReleaseProvider, (_, next) {
    final update = next.valueOrNull;
    if (update == null) return;
    if (ref.read(updatePromptShownProvider)) return;
    ref.read(updatePromptShownProvider.notifier).markShown();
    final installed = ref.read(installedVersionProvider).valueOrNull;
    ref
        .read(appBannerProvider.notifier)
        .setUpdate(
          message: 'A new version is available',
          onUpdate: () => unawaited(
            showUpdateDialog(context, update, installed: installed),
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(showUpdateDialog(context, update, installed: installed));
    });
  });
}

// ---------------------------------------------------------------------------
// Release notes formatting.
// ---------------------------------------------------------------------------

const String _noChangelog = 'No changelog available for this release.';

/// Renders GitHub-flavoured release notes as plain text for the update dialog.
///
/// The notes are written for a browser, not for a 280dp-wide phone dialog.
/// Handing the raw body to a `Text` widget had two visible defects:
///
///  1. Markup leaked through. `### Fixed` printed its own hash characters,
///     list items printed their `-`, and inline `**bold**` / `` `code` ``
///     printed their delimiters.
///  2. The source is hard-wrapped at ~80 columns. Preserved line breaks split
///     sentences mid-clause because `Text` wraps on the newlines it is given
///     as though they were paragraph ends.
///
/// So this strips the markup and *unwraps* the hard wraps, re-joining a
/// continued line onto the bullet or paragraph it belongs to. Section
/// headings are kept, uppercased, because they carry real meaning ("Fixed",
/// "Added") that a flat list would lose.
String formatChangelog(String rawNotes) {
  if (rawNotes.trim().isEmpty) return _noChangelog;

  final normalized = rawNotes
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim();
  final lines = normalized.split('\n');

  // Blocks are flushed in order, so a paragraph is never interleaved with the
  // bullet above it.
  final blocks = <String>[];
  String? openBullet;
  String? openParagraph;

  void flush() {
    if (openBullet != null) {
      final text = _stripInlineMarkdown(openBullet!);
      if (text.isNotEmpty) blocks.add('\u2022 $text');
      openBullet = null;
    }
    if (openParagraph != null) {
      final text = _stripInlineMarkdown(openParagraph!);
      if (text.isNotEmpty) blocks.add(text);
      openParagraph = null;
    }
  }

  for (final line in lines) {
    final trimmed = line.trim();

    // Blank line: ends whatever block was open.
    if (trimmed.isEmpty) {
      flush();
      continue;
    }

    // The generated trailer is GitHub's own boilerplate, not release content.
    // Dropping only its URL would leave a bare "Full Changelog:" line behind.
    if (RegExp(r'^\*\*Full Changelog\*\*').hasMatch(trimmed)) {
      flush();
      continue;
    }

    // A heading starts a new block. `#{1,6}` because GitHub release bodies
    // and release-drafter output use `###`.
    final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      flush();
      final title = _stripInlineMarkdown(heading.group(1) ?? '').toUpperCase();
      if (title.isNotEmpty) blocks.add(title);
      continue;
    }

    // A list item starts a new bullet. Everything indented under it is a
    // continuation and is appended below.
    final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
    if (bullet != null) {
      flush();
      openBullet = bullet.group(1) ?? '';
      continue;
    }

    // A non-indented line with a block already open is a *lazy* continuation:
    // markdown allows the wrap to break before the indent. Append rather than
    // start a new paragraph, joining with a space to undo the hard wrap.
    if (openBullet != null) {
      openBullet = '${openBullet!} $trimmed';
      continue;
    }
    if (openParagraph != null) {
      openParagraph = '${openParagraph!} $trimmed';
      continue;
    }

    // First line of a paragraph.
    openParagraph = trimmed;
  }
  flush();

  if (blocks.isEmpty) return _noChangelog;
  return blocks.join('\n\n');
}

/// Removes inline Markdown delimiters, keeping the text they wrap.
///
/// Handles the forms that actually appear in a release body: emphasis, strong
/// emphasis, inline code, and `[label](url)` links. Backtick spans are
/// stripped before emphasis so that `` `x` `` inside a `**bold**` run does not
/// unbalance the surrounding delimiters.
String _stripInlineMarkdown(String input) {
  var text = input;

  // `[label](url)` becomes `label`. Must run before the bare-URL removal
  // below, otherwise the URL is deleted first and "label](" is left behind.
  text = text.replaceAllMapped(
    RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );

  // Backticks first: a `code` span inside a **bold** run would otherwise
  // unbalance the surrounding `**` and leave one of them behind.
  text = text.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1) ?? '');

  text = text.replaceAllMapped(
    RegExp(r'\*\*\*(.+?)\*\*\*'),
    (m) => m.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'\*\*(.+?)\*\*'),
    (m) => m.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'(?<!\*)\*([^*\n]+)\*(?!\*)'),
    (m) => m.group(1) ?? '',
  );
  text = text.replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1) ?? '');

  // Any remaining bare URL is noise in a phone dialog.
  text = text.replaceAll(RegExp(r'https?://\S+'), '');

  // Collapse the runs of spaces left behind by removed markers and by the
  // hard-wrap joins, then trim.
  return text.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
}

// ---------------------------------------------------------------------------
// Dialog.
// ---------------------------------------------------------------------------

/// Shows the "Update Available" dialog for [update].
///
/// [installed] fills the left-hand chip; when unknown the chip says
/// "Installed" so the arrow still reads as a transition.
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo update, {
  ReleaseVersion? installed,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _UpdateDialog(update: update, installed: installed),
  );
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.update, required this.installed});

  final UpdateInfo update;
  final ReleaseVersion? installed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.card,
          AppSpace.xxxl,
          AppSpace.card,
          AppSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconTile(
              icon: LucideIcons.download,
              size: 52,
              iconSize: 24,
              radius: AppRadius.banner,
            ),
            const SizedBox(height: AppSpace.lg),
            Text('Update available', style: text.titleLarge),
            const SizedBox(height: AppSpace.lg),
            // Wrap, not Row: at 200 % text scale on a narrow phone the two
            // version chips stack instead of overflowing.
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.lg,
              runSpacing: AppSpace.sm,
              children: [
                _VersionChip(label: installed?.label ?? 'Installed'),
                ExcludeSemantics(
                  child: Icon(
                    LucideIcons.arrowRight,
                    size: AppSize.iconSmall,
                    color: c.muted,
                  ),
                ),
                _VersionChip(label: update.versionLabel, selected: true),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: AppRadius.bannerAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "What's new",
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: SingleChildScrollView(
                      child: Text(
                        formatChangelog(update.body),
                        style: text.bodySmall?.copyWith(height: 1.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            PrimaryButton(
              label: 'Update now',
              icon: LucideIcons.download,
              onPressed: () => launchUrl(
                Uri.parse(update.downloadUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            SizedBox(
              width: double.infinity,
              child: LinkButton(
                label: 'Remind me later',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) =>
      AppChip(label: label, selected: selected, showCheck: false);
}
