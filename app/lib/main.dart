import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/brand/brand.dart';
import 'core/router.dart';
import 'features/auth/data/auth_gateway.dart';
import 'features/settings/providers/settings_providers.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kSupabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: kSupabaseUrl,
      publishableKey: kSupabaseAnonKey,
    );
    supabaseAuthReady = true;
  }
  // The full brand lockup is shown here, in Flutter, because the Android 12+
  // system splash only ever draws the launcher tile.
  runApp(const ProviderScope(child: BootSplash(child: MedAIxApp())));
}

class MedAIxApp extends ConsumerWidget {
  const MedAIxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'MedAIx',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: ref.watch(routerProvider),
      // Text scaling is honoured up to 200 %; layouts are built to survive it.
      builder: (context, child) {
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
    );
  }
}
