/// Sign-in and account creation: Google or email.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'theme.dart';

enum _Pending { none, google, email }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _creatingAccount = false;
  var _hidePassword = true;
  var _pending = _Pending.none;
  String? _message;
  var _messageIsError = true;

  bool get _busy => _pending != _Pending.none;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || !email.contains('.')) {
      setState(() {
        _message = 'Enter the email address for your account.';
        _messageIsError = true;
      });
      return;
    }
    if (password.length < 6) {
      setState(() {
        _message = 'Use at least 6 characters for your password.';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _pending = _Pending.email;
      _message = null;
    });

    final gateway = ref.read(authGatewayProvider);
    final result = _creatingAccount
        ? await gateway.signUp(email: email, password: password)
        : await gateway.signIn(email: email, password: password);
    if (!mounted) return;

    setState(() {
      _pending = _Pending.none;
      if (result.needsEmailConfirmation) {
        _creatingAccount = false;
        _message = 'Check your email to confirm your account, then sign in.';
        _messageIsError = false;
      } else if (result.message != null) {
        _message = result.message;
        _messageIsError = true;
      }
    });
  }

  Future<void> _continueWithGoogle() async {
    setState(() {
      _pending = _Pending.google;
      _message = null;
    });
    final result = await ref.read(authGatewayProvider).signInWithGoogle();
    if (!mounted) return;
    setState(() {
      _pending = _Pending.none;
      if (result.message != null) {
        _message = result.message;
        _messageIsError = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(authGatewayProvider).isConfigured;
    return Scaffold(
      appBar: AppBar(title: const Text('MedAIx')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: configured ? _form(context) : const _SetupRequired(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.health_and_safety_outlined, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                _creatingAccount
                    ? 'Create your MedAIx account'
                    : 'Welcome back',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Use Google or email. Either way, your lab reports stay on your account.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 16),
          _AuthBanner(message: _message!, isError: _messageIsError),
        ],
        const SizedBox(height: 16),
        _MethodCard(
          icon: Icons.account_circle_outlined,
          title: 'Google',
          detail:
              'Opens Google, then brings you back to MedAIx. The first time creates your account.',
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _continueWithGoogle,
            icon: _pending == _Pending.google
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_new),
            label: Text(
              _pending == _Pending.google
                  ? 'Opening Google'
                  : 'Continue with Google',
            ),
          ),
        ),
        const SizedBox(height: 12),
        _MethodCard(
          icon: Icons.mail_outline,
          title: 'Email and password',
          detail: _creatingAccount
              ? 'Choose a password of at least 6 characters.'
              : 'Use the email and password for an account you already created.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: _hidePassword,
                autofillHints: _creatingAccount
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    tooltip: _hidePassword ? 'Show password' : 'Hide password',
                    onPressed: () =>
                        setState(() => _hidePassword = !_hidePassword),
                    icon: Icon(
                      _hidePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _pending == _Pending.email
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _creatingAccount
                                ? 'Creating account'
                                : 'Signing in',
                          ),
                        ],
                      )
                    : Text(_creatingAccount ? 'Create account' : 'Sign in'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _creatingAccount = !_creatingAccount;
                        _message = null;
                      }),
                child: Text(
                  _creatingAccount
                      ? 'Already have an account? Sign in'
                      : 'New here? Create an account',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _SetupRequired extends StatelessWidget {
  const _SetupRequired();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sign-in is not configured yet.',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Add SUPABASE_ANON_KEY to api/.env using the publishable key '
          'for fmjcifnrwbazdlrhklta.supabase.co, then run run-app.bat. '
          'Use the publishable key, not the secret key.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _AuthBanner extends StatelessWidget {
  const _AuthBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final semantics = context.semantic;
    final base = isError ? semantics.error : semantics.success;
    final container = isError
        ? semantics.errorContainer
        : semantics.successContainer;
    final onContainer = isError
        ? semantics.onErrorContainer
        : semantics.onSuccessContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: base.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.mark_email_read_outlined,
            color: base,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: onContainer)),
          ),
        ],
      ),
    );
  }
}
