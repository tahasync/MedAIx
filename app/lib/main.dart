import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/brand/brand.dart';
import 'core/error_handling.dart';
import 'core/router.dart';
import 'core/widgets/widgets.dart';
import 'features/auth/data/auth_gateway.dart';
import 'features/settings/providers/settings_providers.dart';
import 'theme/app_theme.dart';

void main() {
  unawaited(
    runZonedGuarded<Future<void>>(() async {
      WidgetsFlutterBinding.ensureInitialized();
      installGlobalErrorHandlers();
      runApp(const ProviderScope(child: BootSplash(child: MedAIxApp())));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initializeSupabase());
      });
    }, reportUnhandledAppError),
  );
}

Future<void> _initializeSupabase() async {
  if (kSupabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: kSupabaseUrl,
        publishableKey: kSupabaseAnonKey,
      );
      supabaseAuthReady = true;
    } on Object catch (error, stack) {
      reportUnhandledAppError(error, stack);
    }
  }
}

class MedAIxApp extends ConsumerWidget {
  const MedAIxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    ref.watch(hapticsEnabledProvider);
    return MaterialApp.router(
      title: 'MedAIx',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: ref.watch(routerProvider),
      // Text scaling is honoured up to 200 %; layouts are built to survive it.
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: unhandledAppError,
        child: child,
        builder: (context, hasError, child) {
          if (hasError) {
            return AppScaffold(
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.screen),
                      child: ErrorState(
                        title: 'MedAIx needs to recover',
                        body:
                            'Something went wrong. Your saved data remains safe.',
                        primaryLabel: 'Return to MedAIx',
                        onPrimary: () => unhandledAppError.value = false,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          final MediaQueryData media = MediaQuery.of(context);
          final TextScaler scaler = media.textScaler.clamp(
            minScaleFactor: 0.8,
            maxScaleFactor: 2.0,
          );
          return MediaQuery(
            data: media.copyWith(textScaler: scaler),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
