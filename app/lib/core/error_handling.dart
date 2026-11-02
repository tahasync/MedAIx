/// Global error capture shared by Flutter's framework, platform and app zones.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'widgets/widgets.dart';

/// Notifies the app shell to replace potentially broken content with recovery copy.
final ValueNotifier<bool> unhandledAppError = ValueNotifier<bool>(false);

/// Installs safe fallbacks without exposing exception messages to patients.
void installGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    reportUnhandledAppError(
      details.exception,
      details.stack ?? StackTrace.current,
    );
  };
  ErrorWidget.builder = safeErrorWidget;
  PlatformDispatcher.instance.onError = (error, stack) {
    reportUnhandledAppError(error, stack);
    return true;
  };
}

/// Records an unhandled error and logs only its type in debug builds.
void reportUnhandledAppError(Object error, StackTrace stack) {
  if (kDebugMode) {
    debugPrint('Unhandled app error (${error.runtimeType}).');
  }
  unhandledAppError.value = true;
}

/// Replaces a failed widget subtree with copy that does not reveal the exception.
Widget safeErrorWidget(FlutterErrorDetails details) => const ErrorState(
  title: 'This screen could not load',
  body: 'MedAIx encountered a problem. Your saved data remains safe.',
);
