/// Sign in or create an account: email + password, or Google.
///
/// Shown without the nav. The router redirects to Home as soon as the
/// gateway reports a session, so this screen never navigates itself.
/// "Create an account" switches to Screen 1 of the questionnaire
/// ([CreateAccountForm]); its answers live in [signUpProvider].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/brand/brand.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../data/auth_gateway.dart';
import '../providers/auth_providers.dart';
import '../providers/sign_up_providers.dart';
import 'create_account_form.dart';

enum _Pending { none, email, google }

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _creatingAccount = false;
  bool _hidePassword = true;
  bool _validateLive = false;
  _Pending _pending = _Pending.none;
  String? _error;

  bool get _busy => _pending != _Pending.none;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String? _validateEmail(String? raw) {
    final String value = (raw ?? '').trim();
    if (value.isEmpty) return 'Enter the email address for your account.';
    if (!_emailPattern.hasMatch(value)) {
      return 'That doesn’t look like an email address.';
    }
    return null;
  }

  /// Existing accounts may predate the 8-character rule, so sign-in only
  /// checks Supabase's minimum.
  String? _validatePassword(String? raw) {
    if ((raw ?? '').length < 6) {
      return 'Use at least 6 characters for your password.';
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _validateLive = true;
      _error = null;
    });
    if (!(_form.currentState?.validate() ?? false)) return;

    setState(() => _pending = _Pending.email);
    final AuthGateway gateway = ref.read(authGatewayProvider);
    final AuthResult result = await gateway.signIn(
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;

    setState(() {
      _pending = _Pending.none;
      if (result.message != null) {
        _error = '${result.message} Nothing has changed on your account.';
      }
    });
  }

  Future<void> _continueWithGoogle() async {
    setState(() {
      _pending = _Pending.google;
      _error = null;
    });
    final AuthResult result = await ref
        .read(authGatewayProvider)
        .signInWithGoogle();
    if (!mounted) return;
    setState(() {
      _pending = _Pending.none;
      if (result.message != null) {
        _error = '${result.message} Nothing has changed on your account.';
      }
    });
  }

  void _toggleMode() {
    setState(() {
      _creatingAccount = !_creatingAccount;
      _error = null;
      _validateLive = false;
      _form.currentState?.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool configured = ref.watch(authGatewayProvider).isConfigured;
    final bool codeStep =
        _creatingAccount &&
        ref.watch(signUpProvider.select((s) => s.stage)) == SignUpStage.code;

    final String title = codeStep
        ? 'Confirm your email'
        : _creatingAccount
        ? 'Create your account'
        : 'Welcome back';
    final String subtitle = codeStep
        ? 'One more step and your account is ready.'
        : _creatingAccount
        ? 'Step 1 of 3 · Takes about 90 seconds.'
        : 'Sign in to see your reports in plain language.';

    return AppScaffold(
      body: AppScreen(
        insetForNav: false,
        children: [
          const SizedBox(height: AppSpace.xl),
          const Center(child: BrandLockup(width: 220)),
          const SizedBox(height: AppSpace.xxxl),
          Semantics(
            header: true,
            child: Text(title, style: text.headlineMedium),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(subtitle, style: text.bodyMedium?.copyWith(color: c.muted)),
          const SizedBox(height: AppSpace.headerGap),
          if (!configured)
            const _NotConfiguredCard()
          else if (_creatingAccount)
            CreateAccountForm(onSignInInstead: _toggleMode)
          else ...[
            _signInCard(),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.lg),
              _InlineError(message: _error!),
            ],
            const SizedBox(height: AppSpace.xl),
            const _OrDivider(),
            const SizedBox(height: AppSpace.xl),
            GhostButton(
              label: 'Continue with Google',
              loading: _pending == _Pending.google,
              onPressed: _busy ? null : _continueWithGoogle,
            ),
          ],
        ],
      ),
    );
  }

  Widget _signInCard() {
    return AppCard(
      child: Form(
        key: _form,
        autovalidateMode: _validateLive
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                validator: _validateEmail,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(LucideIcons.mail),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                controller: _password,
                enabled: !_busy,
                obscureText: _hidePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                validator: _validatePassword,
                onFieldSubmitted: (_) => _busy ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(LucideIcons.lock),
                  suffixIcon: IconButton(
                    tooltip: _hidePassword ? 'Show password' : 'Hide password',
                    onPressed: () =>
                        setState(() => _hidePassword = !_hidePassword),
                    icon: Icon(
                      _hidePassword ? LucideIcons.eye : LucideIcons.eyeOff,
                      size: AppSize.icon,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              PrimaryButton(
                label: 'Sign in',
                loading: _pending == _Pending.email,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: AppSpace.xs),
              LinkButton(
                label: 'New here? Create an account',
                onPressed: _busy ? null : _toggleMode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error tag + plain-language body, shown under the form card.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardTag(
              icon: LucideIcons.triangleAlert,
              label: 'Couldn’t continue',
              color: c.error,
            ),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _NotConfiguredCard extends StatelessWidget {
  const _NotConfiguredCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTag(icon: LucideIcons.wrench, label: 'Setup needed'),
          Text(
            'Sign-in isn’t configured on this build yet.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Launch the app with the Supabase publishable key '
            '(SUPABASE_ANON_KEY), then restart. Nothing on your account is '
            'affected.',
            style: text.bodySmall?.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(child: Divider(color: c.hairline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Text(
            'or',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: c.muted),
          ),
        ),
        Expanded(child: Divider(color: c.hairline)),
      ],
    );
  }
}
