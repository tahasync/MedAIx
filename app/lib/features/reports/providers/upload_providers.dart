/// Upload flow state, kept out of the widget so it survives rebuilds and is
/// testable without a file picker or a camera.
///
/// The picker and the camera-permission request are providers returning
/// functions; widget tests override them to return a path / a grant and
/// never touch a platform channel.
library;

import 'dart:math';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/repositories.dart';
import '../data/report_models.dart';
import '../data/reports_repository.dart';
import 'reports_providers.dart';

/// Where a report file comes from.
enum UploadSource { camera, gallery }

/// Returns the picked file's path, or null when the user cancelled or no
/// picker is available.
typedef PickReportFile = Future<String?> Function(UploadSource source);

/// Outcome of asking for the camera.
class CameraPermission {
  const CameraPermission({
    required this.granted,
    this.permanentlyDenied = false,
  });

  static const CameraPermission allowed = CameraPermission(granted: true);

  final bool granted;

  /// Denied with "don't ask again": the only way back is Settings.
  final bool permanentlyDenied;
}

typedef RequestCameraPermission = Future<CameraPermission> Function();

const MethodChannel _cameraChannel = MethodChannel(
  'com.tahasync.medaix/camera_permission',
);

/// The real picker: `image_picker` for the camera, `file_picker` (jpg, jpeg,
/// png, pdf) for gallery/files. Override in tests.
final filePickerProvider = Provider<PickReportFile>((ref) => pickReportFile);

/// The real permission request. Android goes through the app's own channel
/// (so "don't ask again" is detectable); other platforms let the system
/// picker prompt. Override in tests.
final cameraPermissionProvider = Provider<RequestCameraPermission>(
  (ref) => requestCameraPermission,
);

Future<String?> pickReportFile(UploadSource source) async {
  try {
    switch (source) {
      case UploadSource.camera:
        final XFile? photo = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 90,
          maxWidth: 2500,
        );
        return photo?.path;
      case UploadSource.gallery:
        // file_picker 13: static API, empty list means cancelled.
        final List<fp.PlatformFile> files = await fp.FilePicker.pickFiles(
          type: fp.FileType.custom,
          allowedExtensions: const <String>['jpg', 'jpeg', 'png', 'pdf'],
        );
        return files.isEmpty ? null : files.first.path;
    }
  } on PlatformException {
    // No camera / file manager, or the picker was dismissed.
    return null;
  } on MissingPluginException {
    return null;
  }
}

Future<CameraPermission> requestCameraPermission() async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return CameraPermission.allowed;
  }
  try {
    final Map<String, dynamic>? result = await _cameraChannel
        .invokeMapMethod<String, dynamic>('requestCameraPermission');
    if (result == null) return CameraPermission.allowed;
    return CameraPermission(
      granted: result['granted'] == true,
      permanentlyDenied: result['permanentlyDenied'] == true,
    );
  } on PlatformException {
    return const CameraPermission(granted: false);
  } on MissingPluginException {
    // Channel not registered (tests, desktop): let the picker prompt.
    return CameraPermission.allowed;
  }
}

/// Opens the app's page in system Settings (after "don't ask again").
Future<void> openCameraSettings() async {
  try {
    await _cameraChannel.invokeMethod<void>('openAppSettings');
  } on PlatformException {
    // Nothing to do; the user can still choose a file.
  } on MissingPluginException {
    // Same.
  }
}

// ---------------------------------------------------------------------------
// State machine.
// ---------------------------------------------------------------------------

sealed class UploadState {
  const UploadState();
}

/// Nothing in flight. [hasUploadedBefore] is true after a failure so the
/// empty state can say "Add a report" rather than "No reports yet".
class UploadIdle extends UploadState {
  const UploadIdle({this.hasUploadedBefore = false});

  final bool hasUploadedBefore;
}

class UploadInProgress extends UploadState {
  const UploadInProgress({required this.phase, required this.fileName});

  final UploadPhase phase;
  final String fileName;
}

class UploadSuccess extends UploadState {
  const UploadSuccess({required this.report});

  final LabReport report;

  /// The toast line: "Report ready. 2 values need attention".
  String get toastMessage {
    if (!report.hasSimplified) {
      return 'Report saved. Its explanation is still available to retry.';
    }
    final int n = report.attentionCount;
    if (n == 0) return 'Report ready. All values look normal';
    return n == 1
        ? 'Report ready. 1 value needs attention'
        : 'Report ready. $n values need attention';
  }
}

class UploadFailure extends UploadState {
  const UploadFailure({
    required this.message,
    required this.canRetry,
    required this.filePath,
    required this.language,
    required this.uploadId,
  });

  /// User-safe, from [RepositoryException.message].
  final String message;
  final bool canRetry;
  final String filePath;
  final ReportLanguage language;
  final String uploadId;
}

class UploadController extends Notifier<UploadState> {
  @override
  UploadState build() => const UploadIdle();

  /// Uploads [filePath]. Resolves when the state is success or failure.
  Future<void> submit(
    String filePath, {
    ReportLanguage language = ReportLanguage.english,
    String? uploadId,
  }) async {
    if (state is UploadInProgress) return;
    final String stableUploadId = uploadId ?? _newUploadId();
    final String fileName = _fileName(filePath);
    state = UploadInProgress(phase: UploadPhase.uploading, fileName: fileName);
    try {
      final LabReport report = await ref
          .read(reportsRepositoryProvider)
          .uploadReport(
            filePath,
            language: language,
            uploadId: stableUploadId,
            onPhase: (phase) {
              if (state is UploadInProgress) {
                state = UploadInProgress(phase: phase, fileName: fileName);
              }
            },
          );
      ref.invalidate(reportsListProvider);
      // A new report changes every trend: rebuilding the repository drops
      // its memoised `/risk-trends` answer and the insight/trend providers
      // that watch it refetch on next read.
      ref.invalidate(insightsRepositoryProvider);
      state = UploadSuccess(report: report);
    } on RepositoryException catch (error) {
      state = UploadFailure(
        message: error.message,
        canRetry: error.canRetry,
        filePath: filePath,
        language: language,
        uploadId: stableUploadId,
      );
    } catch (_) {
      state = UploadFailure(
        message: 'Something went wrong while reading the report.',
        canRetry: true,
        filePath: filePath,
        language: language,
        uploadId: stableUploadId,
      );
    }
  }

  /// Re-submits the file that just failed. No-op in any other state.
  Future<void> retry() async {
    final UploadState s = state;
    if (s is! UploadFailure) return;
    await submit(s.filePath, language: s.language, uploadId: s.uploadId);
  }

  /// Back to the empty state ("Choose another file", after success).
  void reset() {
    final bool before = switch (state) {
      UploadIdle(:final hasUploadedBefore) => hasUploadedBefore,
      UploadInProgress() => false,
      UploadSuccess() => true,
      UploadFailure() => true,
    };
    state = UploadIdle(hasUploadedBefore: before);
  }

  static String _fileName(String path) {
    final int cut = path.lastIndexOf(RegExp(r'[\\/]'));
    return cut < 0 ? path : path.substring(cut + 1);
  }

  static String _newUploadId() =>
      'upload_${DateTime.now().microsecondsSinceEpoch}_'
      '${Random.secure().nextInt(1 << 32)}';
}

final uploadControllerProvider =
    NotifierProvider<UploadController, UploadState>(UploadController.new);
