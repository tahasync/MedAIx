/// Screen 1 of 3 — "Create your account" (questionnaire §Screen 1), shown
/// inside [SignInScreen] when the user switches to creating an account.
/// Six required items gate the CTA; then the 6-digit email code step.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../../profile/providers/profile_form.dart';
import '../../profile/ui/profile_fields.dart';
import '../providers/sign_up_providers.dart';

class CreateAccountForm extends ConsumerWidget {
  const CreateAccountForm({super.key, required this.onSignInInstead});

  /// "Already have an account? Sign in".
  final VoidCallback onSignInInstead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SignUpState s = ref.watch(signUpProvider);
    return StateSwitcher(
      child: s.stage == SignUpStage.code
          ? _CodeStep(key: const ValueKey('code'), state: s)
          : _FormStep(
              key: const ValueKey('form'),
              state: s,
              onSignInInstead: onSignInInstead,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// The form
// ---------------------------------------------------------------------------

class _FormStep extends ConsumerStatefulWidget {
  const _FormStep({
    super.key,
    required this.state,
    required this.onSignInInstead,
  });

  final SignUpState state;
  final VoidCallback onSignInInstead;

  @override
  ConsumerState<_FormStep> createState() => _FormStepState();
}

class _FormStepState extends ConsumerState<_FormStep> {
  late final TextEditingController _name = TextEditingController(
    text: widget.state.name,
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.state.email,
  );
  late final TextEditingController _password = TextEditingController(
    text: widget.state.password,
  );
  bool _hidePassword = true;

  SignUpController get _n => ref.read(signUpProvider.notifier);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SignUpState s = widget.state;
    final bool busy = s.pending;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Form(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const Key('signup-name'),
                    controller: _name,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    validator: ProfileValidation.name,
                    onChanged: _n.setName,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(LucideIcons.user),
                      errorMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  TextFormField(
                    key: const Key('signup-email'),
                    controller: _email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    validator: ProfileValidation.email,
                    onChanged: _n.setEmail,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(LucideIcons.mail),
                      errorMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  TextFormField(
                    key: const Key('signup-password'),
                    controller: _password,
                    enabled: !busy,
                    obscureText: _hidePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onChanged: _n.setPassword,
                    decoration: InputDecoration(
                      labelText: 'Create a password',
                      prefixIcon: const Icon(LucideIcons.lock),
                      suffixIcon: IconButton(
                        tooltip: _hidePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () =>
                            setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(
                          _hidePassword ? LucideIcons.eye : LucideIcons.eyeOff,
                          size: AppSize.icon,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  _PasswordChecklist(state: s),
                  const SizedBox(height: AppSpace.lg),
                  DateOfBirthField(
                    key: const Key('signup-dob'),
                    value: s.dateOfBirth,
                    enabled: !busy,
                    errorText: s.dateOfBirthError,
                    onChanged: _n.setDateOfBirth,
                  ),
                  SexAtBirthField(
                    value: s.sexAtBirth,
                    enabled: !busy,
                    onChanged: _n.setSexAtBirth,
                  ),
                  const SectionTitle('Consent'),
                  ConsentSwitches(
                    terms: s.terms,
                    healthData: s.healthData,
                    enabled: !busy,
                    onTermsChanged: _n.setTerms,
                    onHealthDataChanged: _n.setHealthData,
                  ),
                  const SizedBox(height: AppSpace.xl),
                  PrimaryButton(
                    label: 'Create account',
                    loading: busy,
                    onPressed: s.canSubmit && !busy ? _n.submit : null,
                  ),
                  if (!s.canSubmit) ...[
                    const SizedBox(height: AppSpace.md),
                    Text(
                      'Fill in every field and turn on both switches to '
                      'continue.',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(
                        color: context.colors.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpace.xs),
                  LinkButton(
                    label: 'Already have an account? Sign in',
                    onPressed: busy ? null : widget.onSignInInstead,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (s.error != null) ...[
          const SizedBox(height: AppSpace.lg),
          _InlineError(message: s.error!),
        ],
      ],
    );
  }
}

/// 1.3's rule as three lines that turn into checks when satisfied.
class _PasswordChecklist extends StatelessWidget {
  const _PasswordChecklist({required this.state});

  final SignUpState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Requirement(
          met: state.passwordLongEnough,
          text: '8 or more characters',
        ),
        _Requirement(met: state.passwordHasLetter, text: 'At least one letter'),
        _Requirement(met: state.passwordHasNumber, text: 'At least one number'),
      ],
    );
  }
}

class _Requirement extends StatelessWidget {
  const _Requirement({required this.met, required this.text});

  final bool met;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color fg = met ? c.ok : c.muted;
    return Semantics(
      label: '$text: ${met ? 'done' : 'not yet'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
        child: Row(
          children: [
            Icon(
              met ? LucideIcons.circleCheck : LucideIcons.circle,
              size: AppSize.iconTiny,
              color: fg,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The 6-digit code
// ---------------------------------------------------------------------------

class _CodeStep extends ConsumerStatefulWidget {
  const _CodeStep({super.key, required this.state});

  final SignUpState state;

  @override
  ConsumerState<_CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends ConsumerState<_CodeStep> {
  late final TextEditingController _code = TextEditingController(
    text: widget.state.code,
  );

  SignUpController get _n => ref.read(signUpProvider.notifier);

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SignUpState s = widget.state;
    final bool busy = s.pending;
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CardTag(icon: LucideIcons.mail, label: 'Check your email'),
              Text('We sent a code to ${s.email}', style: text.bodyMedium),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Enter the 6-digit code from the email to confirm your '
                'account.',
                style: text.bodySmall?.copyWith(color: c.muted),
              ),
              const SizedBox(height: AppSpace.xl),
              TextField(
                key: const Key('signup-code'),
                controller: _code,
                enabled: !busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(SignUpState.codeLength),
                ],
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                onChanged: _n.setCode,
                onSubmitted: (_) =>
                    s.canVerify && !busy ? _n.verifyCode() : null,
                decoration: const InputDecoration(
                  labelText: '6-digit code',
                  prefixIcon: Icon(LucideIcons.keyRound),
                  counterText: '',
                ),
              ),
              if (s.info != null) ...[
                const SizedBox(height: AppSpace.lg),
                Semantics(
                  liveRegion: true,
                  child: StatusLabel(status: ValueStatus.ok, text: s.info!),
                ),
              ],
              const SizedBox(height: AppSpace.xl),
              PrimaryButton(
                label: 'Confirm code',
                loading: busy,
                onPressed: s.canVerify && !busy ? _n.verifyCode : null,
              ),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  LinkButton(
                    label: 'Send a new code',
                    onPressed: busy ? null : _n.resendCode,
                  ),
                  LinkButton(
                    label: 'Use a different email',
                    onPressed: busy ? null : _n.backToForm,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (s.error != null) ...[
          const SizedBox(height: AppSpace.lg),
          _InlineError(message: s.error!),
        ],
      ],
    );
  }
}

/// Error tag + plain-language body, shown under the card.
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
