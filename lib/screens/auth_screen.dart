import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../services/passwordless_auth_client.dart';
import '../view_models/auth_view_model.dart';

/// Sign-in. Layout only -- the challenge, the attempt count, the resend
/// countdown, and every failure message live in [AuthViewModel].
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key, this.authClient});

  /// Injected by tests; production builds its own.
  final PasswordlessAuthClient? authClient;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AuthViewModel>.reactive(
      viewModelBuilder: () =>
          AuthViewModel(auth: authClient ?? PasswordlessApiAuthClient()),
      builder: (context, model, _) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(IiOsSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: IiOsWidths.form),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: IiOsWordmark(markSize: 42)),
                    IiOsGap.vXxl,
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(IiOsSpacing.xl),
                        child: AutofillGroup(
                          child: model.enteringCode
                              ? _CodeForm(model: model)
                              : _EmailForm(model: model),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Provider buttons plus the email that starts a passwordless challenge.
class _EmailForm extends StatefulWidget {
  const _EmailForm({required this.model});

  final AuthViewModel model;

  @override
  State<_EmailForm> createState() => _EmailFormState();
}

class _EmailFormState extends State<_EmailForm> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _send() => widget.model.sendCode(_email.text);

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final text = Theme.of(context).textTheme;
    final showApple = kIsWeb || defaultTargetPlatform == TargetPlatform.iOS;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Sign in', style: text.headlineSmall),
        IiOsGap.vXxs,
        Text('Continue to your workspace.', style: text.bodySmall),
        IiOsGap.vLg,
        OutlinedButton.icon(
          onPressed: model.isBusy ? null : model.signInWithGoogle,
          icon: const Icon(Icons.g_mobiledata, size: IiOsIconSize.lg),
          label: const Text('Continue with Google'),
        ),
        if (showApple) ...[
          IiOsGap.vXs,
          OutlinedButton.icon(
            onPressed: model.isBusy ? null : model.signInWithApple,
            icon: const Icon(Icons.apple, size: IiOsIconSize.lg),
            label: const Text('Continue with Apple'),
          ),
        ],
        IiOsGap.vLg,
        const _OrEmailDivider(),
        IiOsGap.vMd,
        Text(
          'No password needed. We\u2019ll email you a one-time code.',
          style: text.bodySmall,
        ),
        IiOsGap.vMd,
        TextField(
          controller: _email,
          enabled: !model.isBusy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(),
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(LucideIcons.mail, size: IiOsIconSize.md),
          ),
        ),
        InlineFormError(message: model.errorMessage),
        IiOsGap.vMd,
        FilledButton.icon(
          onPressed: model.isBusy ? null : _send,
          icon: PendingIcon(
            icon: LucideIcons.send,
            pending: model.isBusy,
            pendingLabel: 'Sending your sign-in code',
          ),
          label: const Text('Send sign-in code'),
        ),
      ],
    );
  }
}

/// The six-digit code, with resend and start-over escapes.
class _CodeForm extends StatefulWidget {
  const _CodeForm({required this.model});

  final AuthViewModel model;

  @override
  State<_CodeForm> createState() => _CodeFormState();
}

class _CodeFormState extends State<_CodeForm> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    await widget.model.verifyCode(_code.text);
    // Tells the platform the autofilled code was accepted so it stops
    // offering it.
    TextInput.finishAutofillContext();
  }

  void _startOver() {
    _code.clear();
    widget.model.useDifferentEmail();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final text = Theme.of(context).textTheme;
    final attempts = model.remainingAttempts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Check your email', style: text.headlineSmall),
        IiOsGap.vXxs,
        Text(
          'Enter the 6-digit code sent to ${model.challenge!.email}.',
          style: text.bodySmall,
        ),
        IiOsGap.vLg,
        TextField(
          controller: _code,
          enabled: !model.isBusy,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onChanged: (value) {
            if (value.length == 6 && !model.isBusy) _verify();
          },
          onSubmitted: (_) => _verify(),
          decoration: const InputDecoration(
            labelText: 'Sign-in code',
            hintText: '000000',
            prefixIcon: Icon(LucideIcons.keyRound, size: IiOsIconSize.md),
          ),
        ),
        IiOsGap.vXs,
        Text(
          '$attempts ${attempts == 1 ? 'attempt' : 'attempts'} remaining',
          style: text.bodySmall,
        ),
        InlineFormError(message: model.errorMessage),
        IiOsGap.vMd,
        FilledButton.icon(
          onPressed: model.isBusy ? null : _verify,
          icon: PendingIcon(
            icon: LucideIcons.logIn,
            pending: model.isBusy,
            pendingLabel: 'Checking your code',
          ),
          label: const Text('Continue'),
        ),
        IiOsGap.vXs,
        TextButton(
          onPressed: model.isBusy || !model.canResend
              ? null
              : () => model.sendCode(model.challenge!.email),
          child: Text(
            model.canResend ? 'Resend code' : 'Resend available shortly',
          ),
        ),
        TextButton(
          onPressed: model.isBusy ? null : _startOver,
          child: const Text('Use a different email'),
        ),
      ],
    );
  }
}

/// A rule across the card with EMAIL set into it, separating the federated
/// providers above from the passwordless path below.
class _OrEmailDivider extends StatelessWidget {
  const _OrEmailDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IiOsSpacing.sm),
          child: Text('EMAIL', style: Theme.of(context).textTheme.labelSmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
