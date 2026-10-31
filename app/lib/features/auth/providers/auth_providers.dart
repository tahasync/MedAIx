/// Sign-in state. Tests override [authGatewayProvider] with a fake so
/// widgets never call Supabase.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_gateway.dart';

final authGatewayProvider = Provider<AuthGateway>(
  (ref) => SupabaseAuthGateway(),
);

/// Resolves the first persisted Supabase session before the router chooses
/// between the signed-in app and sign-in. A bounded wait keeps startup moving
/// if auth restoration cannot emit (for example, while offline).
final authBootstrapProvider = FutureProvider<void>((ref) async {
  final AuthGateway gateway = ref.watch(authGatewayProvider);
  // Supabase.initialize restores its persisted session before runApp. The
  // synchronous session read in AuthController is authoritative here; the
  // AppShell keeps the account setup screen visible while profile data loads.
  if (!gateway.isConfigured) return;
});

/// Current session. Null means the sign-in screen is showing.
class AuthController extends Notifier<AuthSession?> {
  @override
  AuthSession? build() {
    final gateway = ref.watch(authGatewayProvider);
    final subscription = gateway.authStateChanges.listen((session) {
      state = session;
    });
    ref.onDispose(subscription.cancel);
    return gateway.currentSession;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthSession?>(
  AuthController.new,
);
