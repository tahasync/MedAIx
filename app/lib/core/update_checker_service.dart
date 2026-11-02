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
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

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
/// Mirrors pubspec's `version: 0.1.3+4`: [build] is the `+4`, which Flutter
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
    } on Object catch (_) {
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
  } on Object catch (_) {
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
