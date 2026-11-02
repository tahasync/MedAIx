import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/core/router.dart';
import 'package:tahasync_medaix/core/widgets/widgets.dart';
import 'package:tahasync_medaix/data/api/api_client.dart';
import 'package:tahasync_medaix/data/fake/fake_repositories.dart';
import 'package:tahasync_medaix/data/repositories.dart';
import 'package:tahasync_medaix/features/reports/data/report_models.dart';
import 'package:tahasync_medaix/features/reports/data/reports_repository.dart';
import 'package:tahasync_medaix/features/reports/providers/upload_providers.dart';
import 'package:tahasync_medaix/features/reports/ui/upload_screen.dart';

import 'support/test_app.dart';

const String kPickedPath = 'C:/photos/report.jpg';

class ExpiredSessionReportsRepository extends FakeReportsRepository {
  ExpiredSessionReportsRepository()
    : super(latency: Duration.zero, uploadDelay: Duration.zero);

  @override
  Future<LabReport> uploadReport(
    String filePath, {
    ReportLanguage language = ReportLanguage.english,
    String? uploadId,
    void Function(UploadPhase phase)? onPhase,
  }) async => throw RepositoryException(
    'Please sign in to continue.',
    canRetry: false,
    cause: ApiException('Please sign in to continue.', statusCode: 401),
  );
}

/// Picker and permission stand-ins: no platform channels in tests.
List<Override> pickerOverrides({
  String? path = kPickedPath,
  CameraPermission permission = CameraPermission.allowed,
  List<UploadSource>? picked,
}) {
  return <Override>[
    filePickerProvider.overrideWithValue((source) async {
      picked?.add(source);
      return path;
    }),
    cameraPermissionProvider.overrideWithValue(() async => permission),
  ];
}

Future<void> pumpUpload(
  WidgetTester tester, {
  FakeReportsRepository? reports,
  List<Override> extra = const <Override>[],
}) async {
  await usePhone(tester);
  await tester.pumpWidget(
    testAppAt(
      AppRoutes.upload,
      overrides: <Override>[
        ...fakeOverrides(reports: reports),
        ...pickerOverrides(),
        ...extra,
      ],
    ),
  );
  await tester.pumpAndSettle();
}

/// Lets a toast finish so no timer is pending when the test ends.
Future<void> settleToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  group('empty', () {
    testWidgets('shows both actions, language chips and the offline note', (
      tester,
    ) async {
      await pumpUpload(tester);

      expect(find.text('Upload report'), findsOneWidget);
      expect(find.text('Scan a report'), findsOneWidget);
      expect(find.text('Choose from gallery or files'), findsOneWidget);
      for (final label in ['English', 'Urdu', 'Roman Urdu']) {
        expect(find.widgetWithText(AppChip, label), findsOneWidget);
      }
      expect(
        find.text('Works offline. Reports sync when you reconnect.'),
        findsOneWidget,
      );
      // Reports already exist in the default fake.
      expect(find.text('Add a report'), findsOneWidget);
    });

    testWidgets('says "No reports yet" for a first-time user', (tester) async {
      await pumpUpload(
        tester,
        reports: FakeReportsRepository(
          latency: Duration.zero,
          uploadDelay: Duration.zero,
          seed: const [],
        ),
      );
      expect(find.text('No reports yet'), findsOneWidget);
    });

    testWidgets('language chips are single-select', (tester) async {
      await pumpUpload(tester);
      await tester.tap(find.widgetWithText(AppChip, 'Urdu'));
      await tester.pumpAndSettle();

      AppChip chip(String label) =>
          tester.widget<AppChip>(find.widgetWithText(AppChip, label));
      expect(chip('Urdu').selected, isTrue);
      expect(chip('English').selected, isFalse);
      expect(chip('Roman Urdu').selected, isFalse);
    });
  });

  group('reading', () {
    testWidgets('shows the progress bar and skeleton while uploading', (
      tester,
    ) async {
      await pumpUpload(
        tester,
        reports: FakeReportsRepository(
          latency: Duration.zero,
          uploadDelay: const Duration(milliseconds: 600),
        ),
      );

      await tester.tap(find.text('Choose from gallery or files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Reading your report'), findsOneWidget);
      expect(
        find.text('Sending the report and reading its text'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(SkeletonBox), findsWidgets);

      // The fake repository moves to checking values without inventing a %.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Checking the values we could read'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('In plain words'), findsOneWidget);
      await settleToast(tester);
    });
  });

  group('error', () {
    testWidgets('unreadable photo: message, data safety, no Try again', (
      tester,
    ) async {
      await pumpUpload(
        tester,
        reports: FakeReportsRepository(
          latency: Duration.zero,
          uploadDelay: Duration.zero,
          failNextUpload: true,
        ),
      );

      await tester.tap(find.text('Choose from gallery or files'));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('We couldn’t read this report'), findsOneWidget);
      expect(
        find.text(
          'Retake the photo in good light with the whole page in frame.',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);

      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();
      expect(find.text('In plain words'), findsOneWidget);
    });

    testWidgets('retryable failure offers Try again', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(
        testAppAt(
          AppRoutes.upload,
          overrides: <Override>[
            reportsRepositoryProvider.overrideWithValue(
              const FailingReportsRepository('The service took too long.'),
            ),
            ...pickerOverrides(),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose from gallery or files'));
      await tester.pumpAndSettle();

      expect(find.text('Couldn’t read this photo'), findsOneWidget);
      expect(find.textContaining('The service took too long.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t read this photo'), findsOneWidget);
    });
  });

  group('success', () {
    testWidgets('toasts and opens the new report', (tester) async {
      await pumpUpload(tester);

      await tester.tap(find.text('Choose from gallery or files'));
      await tester.pumpAndSettle();

      expect(
        find.text('Report ready. 2 values need attention'),
        findsOneWidget,
      );
      expect(find.text('In plain words'), findsOneWidget);
      expect(find.text('HbA1c'), findsOneWidget);
      await settleToast(tester);
    });

    testWidgets('a cancelled picker stays on the empty state', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(
        testAppAt(
          AppRoutes.upload,
          overrides: <Override>[
            ...fakeOverrides(),
            ...pickerOverrides(path: null),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose from gallery or files'));
      await tester.pumpAndSettle();
      expect(find.text('Scan a report'), findsOneWidget);
      expect(find.byType(ErrorCard), findsNothing);
    });
  });

  group('camera permission', () {
    testWidgets('explains before asking, then opens the camera', (
      tester,
    ) async {
      final picked = <UploadSource>[];
      await usePhone(tester);
      await tester.pumpWidget(
        testAppAt(
          AppRoutes.upload,
          overrides: <Override>[
            ...fakeOverrides(),
            ...pickerOverrides(picked: picked),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scan a report'));
      await tester.pumpAndSettle();
      expect(find.text('Camera access needed'), findsOneWidget);
      expect(find.text('Allow camera'), findsOneWidget);
      expect(find.text('Choose a file instead'), findsOneWidget);
      expect(picked, isEmpty);

      await tester.tap(find.text('Allow camera'));
      await tester.pumpAndSettle();
      expect(picked, <UploadSource>[UploadSource.camera]);
      expect(find.text('In plain words'), findsOneWidget);
      await settleToast(tester);
    });

    testWidgets('denied: explains and keeps the file fallback', (tester) async {
      final picked = <UploadSource>[];
      await usePhone(tester);
      await tester.pumpWidget(
        testAppAt(
          AppRoutes.upload,
          overrides: <Override>[
            ...fakeOverrides(),
            ...pickerOverrides(
              picked: picked,
              permission: const CameraPermission(granted: false),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scan a report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow camera'));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('MedAIx needs camera access to scan'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(picked, isEmpty);

      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();
      expect(picked, <UploadSource>[UploadSource.gallery]);
      expect(find.text('In plain words'), findsOneWidget);
      await settleToast(tester);
    });

    testWidgets('permanently denied points to Settings', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(
        testAppAt(
          AppRoutes.upload,
          overrides: <Override>[
            ...fakeOverrides(),
            ...pickerOverrides(
              permission: const CameraPermission(
                granted: false,
                permanentlyDenied: true,
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scan a report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow camera'));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('MedAIx needs camera access to scan'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
    });

    testWidgets('gallery permission denial offers settings and recovery', (
      tester,
    ) async {
      await usePhone(tester);
      await tester.pumpWidget(
        testAppAt(
          AppRoutes.upload,
          overrides: <Override>[
            ...fakeOverrides(),
            filePickerProvider.overrideWithValue((_) async {
              throw const FilePermissionDenied();
            }),
            cameraPermissionProvider.overrideWithValue(
              () async => CameraPermission.allowed,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose from gallery or files'));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorState), findsOneWidget);
      expect(
        find.text('MedAIx needs photo access to add a report'),
        findsOneWidget,
      );
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
    });

    testWidgets(
      'expired session asks for sign-in and preserves pending upload',
      (tester) async {
        await usePhone(tester);
        await tester.pumpWidget(
          testAppAt(
            AppRoutes.upload,
            overrides: <Override>[
              ...fakeOverrides(reports: ExpiredSessionReportsRepository()),
              ...pickerOverrides(),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Choose from gallery or files'));
        await tester.pumpAndSettle();
        expect(find.byType(ErrorState), findsOneWidget);
        expect(find.text('Please sign in again'), findsOneWidget);

        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();
        expect(find.text('Welcome back'), findsOneWidget);

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.text('Welcome back')),
        );
        final UploadFailure pending =
            container.read(uploadControllerProvider) as UploadFailure;
        expect(pending.filePath, kPickedPath);
        expect(pending.uploadId, isNotEmpty);
      },
    );
  });

  group('layout', () {
    testWidgets('no overflow at 320 dp', (tester) async {
      await usePhone(tester, size: const Size(320, 640));
      await tester.pumpWidget(
        testAppAt(
          AppRoutes.upload,
          overrides: <Override>[...fakeOverrides(), ...pickerOverrides()],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Scan a report'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 200 % text scale', (tester) async {
      await usePhone(tester, size: const Size(320, 640));
      await tester.pumpWidget(
        testScreen(
          const UploadScreen(),
          overrides: pickerOverrides(),
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Scan a report'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
