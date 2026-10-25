/// Sign-in state. Tests override [authGatewayProvider] with a fake so
/// widgets never call Supabase.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_gateway.dart';

final authGatewayProvider = Provider<AuthGateway>(
  (ref) => SupabaseAuthGateway(),
);

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
