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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import 'widgets/widgets.dart';

class AppUpdateConfig {
  const AppUpdateConfig._();

  static const String repoOwner = 'tahasync';
  static const String repoName = 'MedAIx';
  static const String apiUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';
  static const String latestReleaseUrl =
      'https://github.com/$repoOwner/$repoName/releases/latest';

  /// Debug aid: treat whatever release is fetched as newer than the installed
  /// build, so the dialog can be exercised on a device that is already on the
  /// latest release. Defaults to false and must never be set in CI:
  /// `flutter build apk --debug --dart-define=UPDATE_CHECK_FORCE=true`
  static const bool forceUpdate = bool.fromEnvironment('UPDATE_CHECK_FORCE');

  /// Upper bound on the GitHub round-trip. The prompt is a courtesy, not a
  /// gate, so a slow network must never hold anything up for long.
  static const Duration timeout = Duration(seconds: 10);
}

/// A `major.minor.patch` version plus the Android build number.
///
/// Mirrors pubspec's `version: 0.1.2+3`: [build] is the `+3`, which Flutter
/// writes as `versionCode` and `PackageInfo` reports as `buildNumber`.
@immutable
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(this.major, this.minor, this.patch, {this.build = 0});

  final int major;
  final int minor;
  final int patch;
  final int build;

  /// `v0.1.1+2`, or `v0.1.1` when the build is unknown.
  String get label => 'v$major.$minor.$patch${build > 0 ? '+$build' : ''}';

  ReleaseVersion withBuild(int build) =>
      ReleaseVersion(major, minor, patch, build: build);

  @override
  int compareTo(ReleaseVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  @override
  bool operator ==(Object other) =>
      other is ReleaseVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch &&
      other.build == build;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);

  @override
  String toString() => label;
}

/// The workflow's asset slug: `...-v0.1.1-2-release.apk`.
final RegExp _apkAssetPattern = RegExp(
  r'-v(\d+)\.(\d+)\.(\d+)-(\d+)-release\.apk$',
  caseSensitive: false,
);

/// A plain version string or tag: `v0.1.1`, `0.1.1`, `v0.1.1+2`, `v0.1.1-2`.
final RegExp _versionPattern = RegExp(
  r'^v?(\d+)\.(\d+)\.(\d+)(?:[+-](\d+))?$',
  caseSensitive: false,
);

/// Reads a [ReleaseVersion] out of an APK asset name or a release tag.
///
/// Pure: no I/O, no platform calls. Returns null for anything that is neither
/// the workflow's APK slug nor a `v?X.Y.Z` string, which includes MedAIx's
/// sprint tags such as `sprint-2-wk-03-04`.
ReleaseVersion? parseReleaseVersion(String source) {
  final text = source.trim();
  if (text.isEmpty) return null;

  final asset = _apkAssetPattern.firstMatch(text);
  if (asset != null) {
    return ReleaseVersion(
      int.parse(asset.group(1)!),
      int.parse(asset.group(2)!),
      int.parse(asset.group(3)!),
      build: int.parse(asset.group(4)!),
    );
  }

  final tag = _versionPattern.firstMatch(text);
  if (tag != null) {
    return ReleaseVersion(
      int.parse(tag.group(1)!),
      int.parse(tag.group(2)!),
      int.parse(tag.group(3)!),
      build: int.tryParse(tag.group(4) ?? '') ?? 0,
    );
  }

  return null;
}

/// True when [remote] should be offered over [installed]: a greater version,
/// or the same version with a greater build number.
///
/// Pure, so the comparison is unit-testable without a device or the network.
bool isNewerVersion(ReleaseVersion installed, ReleaseVersion remote) =>
    remote.compareTo(installed) > 0;

/// What the dialog needs from one GitHub release.
@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.tagName,
    required this.htmlUrl,
    required this.body,
    required this.publishedAt,
    this.version,
    this.apkUrl,
  });

  /// Raw release tag, e.g. `sprint-2-wk-03-04`.
  final String tagName;

  /// The release page on GitHub.
  final String htmlUrl;

  /// Release notes in GitHub markdown. See [formatChangelog].
  final String body;

  final DateTime publishedAt;

  /// Parsed from the APK asset name, else the tag. Null when neither parses.
  final ReleaseVersion? version;

  /// `browser_download_url` of the release's APK asset, when it has one.
  final String? apkUrl;

  /// Where "Update Now" goes: the APK itself when there is one, so the phone
  /// starts downloading; otherwise the release page.
  String get downloadUrl {
    final apk = apkUrl;
    if (apk != null && apk.isNotEmpty) return apk;
    if (htmlUrl.isNotEmpty) return htmlUrl;
    return AppUpdateConfig.latestReleaseUrl;
  }

  /// Text for the "latest" chip: the parsed version, else the raw tag.
  String get versionLabel => version?.label ?? tagName;

  /// Builds an [UpdateInfo] from the `releases/latest` JSON. Pure.
  ///
  /// Returns null when the payload has no tag at all. A release whose
  /// version cannot be determined is still returned (with [version] null) so
  /// the caller can decide; [UpdateChecker.checkForUpdate] treats it as "no
  /// update".
  static UpdateInfo? fromJson(Map<String, dynamic> data) {
    final tag = (data['tag_name'] as String?)?.trim() ?? '';
    if (tag.isEmpty) return null;

    String? apkName;
    String? apkUrl;
    final assets = data['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name'] as String? ?? '';
        if (!name.toLowerCase().endsWith('.apk')) continue;
        apkName = name;
        apkUrl = asset['browser_download_url'] as String?;
        // Prefer an asset that carries the version slug; keep scanning only
        // if this one does not.
        if (parseReleaseVersion(name) != null) break;
      }
    }

    final version =
        (apkName == null ? null : parseReleaseVersion(apkName)) ??
        parseReleaseVersion(tag);

    return UpdateInfo(
      tagName: tag,
      htmlUrl: data['html_url'] as String? ?? '',
      body: data['body'] as String? ?? '',
      publishedAt:
          DateTime.tryParse(data['published_at'] as String? ?? '') ??
          DateTime.now(),
      version: version,
      apkUrl: apkUrl,
    );
  }
}

/// Fetches the latest GitHub release and decides whether it is an update.
///
/// Every failure (offline, rate-limited, malformed JSON) collapses to null:
/// the prompt is a courtesy and must never surface an error of its own.
class UpdateChecker {
  UpdateChecker({http.Client? client, bool? forceUpdate})
    : _client = client ?? http.Client(),
      forceUpdate = forceUpdate ?? AppUpdateConfig.forceUpdate;

  final http.Client _client;

  /// See [AppUpdateConfig.forceUpdate].
  final bool forceUpdate;

  void dispose() => _client.close();

  /// The latest release, or null if it could not be fetched or parsed.
  Future<UpdateInfo?> fetchLatestRelease() async {
    try {
      final response = await _client
          .get(
            Uri.parse(AppUpdateConfig.apiUrl),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(AppUpdateConfig.timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return UpdateInfo.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// The latest release if it is newer than [installed], else null.
  ///
  /// With [forceUpdate] any fetched release counts, which is how the dialog is
  /// demonstrated on a device already running the newest build.
  Future<UpdateInfo?> checkForUpdate({
    required ReleaseVersion? installed,
  }) async {
    if (installed == null && !forceUpdate) return null;
    final latest = await fetchLatestRelease();
    if (latest == null) return null;
    if (forceUpdate) return latest;
    final remote = latest.version;
    if (remote == null) return null;
    return isNewerVersion(installed!, remote) ? latest : null;
  }
}

/// Reads the installed version and build from the platform.
///
/// Null when the platform channel is unavailable (e.g. in widget tests), in
/// which case no comparison is possible and no update is offered.
Future<ReleaseVersion?> readInstalledVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final base = parseReleaseVersion(info.version);
    if (base == null) return null;
    return base.withBuild(int.tryParse(info.buildNumber) ?? 0);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Riverpod wiring. Mirrors `apiClientProvider` in providers.dart: the service
// owns an http.Client that Riverpod disposes, and tests override the provider.
// ---------------------------------------------------------------------------

/// GitHub release client, disposed by Riverpod.
final updateCheckerProvider = Provider<UpdateChecker>((ref) {
  final checker = UpdateChecker();
  ref.onDispose(checker.dispose);
  return checker;
});

/// The running app's version and build, read once per [ProviderScope].
final installedVersionProvider = FutureProvider<ReleaseVersion?>(
  (ref) => readInstalledVersion(),
);

/// The latest release when it is newer than the installed build, else null.
///
/// `autoDispose` so the check runs when the home screen first listens and is
/// dropped with it; [updatePromptShownProvider] stops a later rebuild from
/// prompting a second time in the same session.
final latestReleaseProvider = FutureProvider.autoDispose<UpdateInfo?>((
  ref,
) async {
  final installed = await ref.watch(installedVersionProvider.future);
  return ref.read(updateCheckerProvider).checkForUpdate(installed: installed);
});

/// True once the prompt has been shown in this session.
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      showUpdateDialog(context, update, installed: installed);
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
