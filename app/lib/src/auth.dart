/// Supabase Auth session used by the Flutter client.
///
/// The app signs in against the hosted project. Report rows stay in the
/// MedAIx API; this file only obtains an access token to send as a bearer.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Hosted project. Override with `--dart-define=SUPABASE_URL=...`.
const String kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://fmjcifnrwbazdlrhklta.supabase.co',
);

/// Publishable (anon) key. Empty until the app is launched with
/// `--dart-define=SUPABASE_ANON_KEY=...`. Never put the secret key here.
const String kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Set from `main` after [Supabase.initialize] succeeds.
bool supabaseAuthReady = false;

/// A signed-in Supabase user, reduced to what the API client needs.
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.accessToken,
    this.email,
  });

  final String userId;
  final String accessToken;
  final String? email;
}

/// Outcome of a sign-in or sign-up attempt. [message] is already safe to show.
class AuthResult {
  const AuthResult({this.message, this.needsEmailConfirmation = false});

  final String? message;
  final bool needsEmailConfirmation;

  bool get ok => message == null;
}

/// Sign-in operations. Widget tests supply a fake so they never call Supabase.
abstract class AuthGateway {
  bool get isConfigured;

  AuthSession? get currentSession;

  Stream<AuthSession?> get authStateChanges;

  Future<AuthResult> signIn({required String email, required String password});

  Future<AuthResult> signUp({required String email, required String password});

  Future<AuthResult> signInWithGoogle();

  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  @override
  bool get isConfigured => supabaseAuthReady;

  @override
  AuthSession? get currentSession {
    if (!isConfigured) return null;
    return _from(Supabase.instance.client.auth.currentSession);
  }

  @override
  Stream<AuthSession?> get authStateChanges {
    if (!isConfigured) return const Stream.empty();
    return Supabase.instance.client.auth.onAuthStateChange.map(
      (event) => _from(event.session),
    );
  }

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    if (!isConfigured) return const AuthResult(message: _missingKeyMessage);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return const AuthResult();
    } on AuthException catch (error) {
      return AuthResult(message: _messageFor(error));
    } catch (_) {
      return const AuthResult(
        message: 'Could not reach the sign-in service. Try again.',
      );
    }
  }

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
  }) async {
    if (!isConfigured) return const AuthResult(message: _missingKeyMessage);
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );
      if (response.session == null) {
        return const AuthResult(needsEmailConfirmation: true);
      }
      return const AuthResult();
    } on AuthException catch (error) {
      return AuthResult(message: _messageFor(error, signingUp: true));
    } catch (_) {
      return const AuthResult(
        message: 'Could not reach the sign-in service. Try again.',
      );
    }
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    if (!isConfigured) return const AuthResult(message: _missingKeyMessage);
    try {
      final opened = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kOAuthRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!opened) {
        return const AuthResult(message: 'Google sign-in was cancelled.');
      }
      return const AuthResult();
    } on AuthException catch (error) {
      return AuthResult(message: _messageFor(error));
    } catch (_) {
      return const AuthResult(
        message: 'Could not reach Google sign-in. Try again.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    if (!isConfigured) return;
    await Supabase.instance.client.auth.signOut();
  }

  AuthSession? _from(Session? session) {
    if (session == null || session.accessToken.isEmpty) return null;
    return AuthSession(
      userId: session.user.id,
      accessToken: session.accessToken,
      email: session.user.email,
    );
  }

  String _messageFor(AuthException error, {bool signingUp = false}) {
    final message = error.message.toLowerCase();
    if (message.contains('cancel')) {
      return 'Google sign-in was cancelled.';
    }
    if (message.contains('not enabled')) {
      return 'Google sign-in is not turned on yet. Enable it in Supabase, then try again.';
    }
    if (message.contains('rate limit')) {
      return 'Supabase stopped the confirmation email because too many were sent. '
          'Wait about an hour, or turn off Confirm email in the Supabase dashboard and try again.';
    }
    if (message.contains('not confirmed')) {
      return 'Confirm that email first, then sign in. Check the inbox for the message from Supabase.';
    }
    if (message.contains('invalid') && message.contains('email')) {
      return 'That email address was rejected. Use the address you can open.';
    }
    if (message.contains('invalid login') ||
        message.contains('invalid credentials')) {
      return 'That email or password is incorrect.';
    }
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return 'An account with that email already exists. Sign in instead.';
    }
    if (message.contains('password')) {
      return 'Use at least 6 characters for your password.';
    }
    if (signingUp) {
      return 'Could not create the account. Check the email and password, then try again.';
    }
    return 'Could not sign in. Check your email and password, then try again.';
  }
}

/// Where Google sends the browser after sign-in. Must match the Android
/// intent filter and the Supabase redirect allow-list.
const String kOAuthRedirectUrl = 'com.tahasync.medaix://login-callback';

const String _missingKeyMessage =
    'Sign-in is not configured yet. Add the Supabase publishable key and restart the app.';
