import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/brand_mark.dart';
import '../core/widgets/message_banner.dart';
import 'forgot_password_screen.dart';
import 'sign_up_screen.dart';
import 'validators.dart';

/// Email + password sign-in.
///
/// On success nothing here navigates: `authStateChanges` fires, and the
/// AuthGate above swaps this screen for the dashboard.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    // Dismiss the keyboard so the error banner isn't hidden behind it.
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthRepository>();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await auth.signIn(email: _email.text, password: _password.text);
      // The gate takes it from here.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s6,
              vertical: Tokens.s8,
            ),
            child: ConstrainedBox(
              // Keeps the form a readable column on a tablet or a foldable
              // instead of stretching the fields across the whole width.
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: BrandMark(),
                      ),
                      const SizedBox(height: Tokens.s10),

                      Text('Welcome back', style: text.headlineLarge),
                      const SizedBox(height: Tokens.s2),
                      Text(
                        'Sign in to pick up your prep where you left off.',
                        style: text.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: Tokens.s8),

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
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.username],
                        validator: Validators.email,
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                      ),
                      const SizedBox(height: Tokens.s4),

                      TextFormField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        enabled: !_busy,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            tooltip:
                                _obscure ? 'Show password' : 'Hide password',
                          ),
                        ),
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        // Only "is it empty" on sign-in: an existing account may
                        // predate the length rule, and rejecting it here would
                        // lock the student out of their own password.
                        validator: (v) => Validators.required(v, 'password'),
                        onFieldSubmitted: (_) => _submit(),
                      ),

                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => _open(
                                    ForgotPasswordScreen(
                                      initialEmail: _email.text,
                                    ),
                                  ),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      const SizedBox(height: Tokens.s3),

                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const _ButtonSpinner()
                            : const Text('Sign in'),
                      ),
                      const SizedBox(height: Tokens.s8),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'New to NLTC?',
                            style: text.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _open(const SignUpScreen()),
                            child: const Text('Create an account'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spinner sized to sit inside a button without changing its height.
class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      );
}
