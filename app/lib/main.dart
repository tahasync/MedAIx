import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/auth.dart';
import 'src/providers.dart';
import 'src/router.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kSupabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: kSupabaseUrl,
      publishableKey: kSupabaseAnonKey,
    );
    supabaseAuthReady = true;
  }
  runApp(const ProviderScope(child: MedAIxApp()));
}

class MedAIxApp extends ConsumerWidget {
  const MedAIxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final session = ref.watch(authControllerProvider);

    return MaterialApp(
      key: ValueKey(session?.userId ?? 'signed-out'),
      title: 'MedAIx',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      initialRoute: session == null ? AppRouter.signIn : AppRouter.home,
      // `/sign-in` must not also push `/`. Otherwise Back lands on the
      // profile gate, which has no session and only offers a dead-end retry.
      onGenerateInitialRoutes: (String initialRoute) {
        return <Route<dynamic>>[
          AppRouter.onGenerateRoute(RouteSettings(name: initialRoute)),
        ];
      },
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
