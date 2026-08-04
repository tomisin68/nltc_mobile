import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/message_banner.dart';
import 'validators.dart';

/// Sends a Firebase password-reset email.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  /// Carried over from the sign-in form so the student doesn't retype it.
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);

  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthRepository>();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await auth.sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on AuthFailure catch (e) {
      // `user-not-found` is deliberately not special-cased: telling a stranger
      // which addresses have accounts is an account-enumeration leak.
      if (e.code == 'user-not-found') {
        if (mounted) setState(() => _sent = true);
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Tokens.s6,
            Tokens.s4,
            Tokens.s6,
            Tokens.s8,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _sent
                  ? _SentConfirmation(email: _email.text.trim())
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Forgot your password?',
                            style: text.headlineMedium,
                          ),
                          const SizedBox(height: Tokens.s2),
                          Text(
                            'Enter the email address on your account and we '
                            'will send you a link to set a new password.',
                            style: text.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: Tokens.s6),

                          if (_error != null) ...[
                            MessageBanner(message: _error!),
                            const SizedBox(height: Tokens.s5),
                          ],

                          TextFormField(
                            controller: _email,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Email address',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            autofocus: true,
                            autofillHints: const [AutofillHints.username],
                            validator: Validators.email,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: Tokens.s6),

                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: scheme.onPrimary,
                                    ),
                                  )
                                : const Text('Send reset link'),
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

class _SentConfirmation extends StatelessWidget {
  const _SentConfirmation({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Tokens.s6),
        Icon(Icons.mark_email_read_outlined, size: 64, color: scheme.primary),
        const SizedBox(height: Tokens.s6),
        Text(
          'Check your email',
          style: text.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Tokens.s3),
        Text(
          'If an account exists for $email, a reset link is on its way. '
          'It can take a minute to arrive — remember to look in spam.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Tokens.s8),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}
