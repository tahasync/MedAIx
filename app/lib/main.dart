import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/theme.dart';
import 'src/router.dart';

void main() {
  runApp(
    ProviderScope(
      child: const MedAIxApp(),
    ),
  );
}

class MedAIxApp extends ConsumerWidget {
  const MedAIxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'MedAIx',
      theme: liquidGlassTheme(),
      routerConfig: router ?? appRouter,
    );
  }
}
