import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/services/api_client.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/message_banner.dart';
import 'validators.dart';

/// Exams a student can be preparing for. Same list, same order and same
/// spelling as the web signup form — the admin panel filters on these strings.
const _targetExams = [
  'JAMB',
  'WAEC',
  'NECO',
  'GCE',
  'POST-UTME',
  'MULTIPLE',
  'BECE (JSS)',
];

const _nigerianStates = [
  'Abia', 'Adamawa', 'Akwa Ibom', 'Anambra', 'Bauchi', 'Bayelsa', 'Benue',
  'Borno', 'Cross River', 'Delta', 'Ebonyi', 'Edo', 'Ekiti', 'Enugu', 'FCT',
  'Gombe', 'Imo', 'Jigawa', 'Kaduna', 'Kano', 'Katsina', 'Kebbi', 'Kogi',
  'Kwara', 'Lagos', 'Nasarawa', 'Niger', 'Ogun', 'Ondo', 'Osun', 'Oyo',
  'Plateau', 'Rivers', 'Sokoto', 'Taraba', 'Yobe', 'Zamfara',
];

/// Creates a student account and its `users/{uid}` profile.
///
/// Every account made here starts on the 3-day free trial that
/// [AuthRepository.signUp] writes, and in the `online` cohort — the app has no
/// physical-centre signup path.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  String _targetExam = _targetExams.first;
  String _state = 'Lagos';

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthRepository>();
    final api = context.read<ApiClient>();
    final session = context.read<SessionController>();
    final navigator = Navigator.of(context);

    // Read off the form now. This screen is popped the moment signup succeeds,
    // which disposes the controllers underneath any work still running.
    final signup = <String, dynamic>{
      'firstName': _firstName.text.trim(),
      'lastName': _lastName.text.trim(),
      'phone': _phone.text.trim(),
      'state': _state,
      'targetExam': _targetExam,
      'plan': 'free',
    };

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await auth.signUp(
        email: _email.text,
        password: _password.text,
        firstName: _firstName.text,
        lastName: _lastName.text,
        phone: _phone.text,
        targetExam: _targetExam,
        state: _state,
      );

      // The same call the website makes after signup: it puts the new student
      // in front of the admins and sends the welcome message. Deliberately not
      // awaited — the trial is already on the profile this device just wrote,
      // so there is nothing here worth holding a student behind a spinner for
      // while Render wakes up.
      unawaited(_announceSignup(api, session, signup));

      // The gate has already swapped the root route to the dashboard beneath
      // us; drop this screen so the student lands on it rather than on a form
      // they can still back into.
      if (mounted) navigator.popUntil((r) => r.isFirst);
    } on AuthFailure catch (e) {
      // The account itself could not be created — nothing to recover.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      // Anything else means the Firebase account exists but its profile
      // document did not land. Left alone that student is signed in with no
      // profile and so no trial — the one way to be locked out on day one. The
      // backend writes the same document from the ID token, trial included, so
      // ask it to before admitting defeat. Worth waiting for: there is no
      // account to use until it comes back.
      final recovered = await _announceSignup(api, session, signup);
      if (!mounted) return;
      if (recovered) {
        navigator.popUntil((r) => r.isFirst);
      } else {
        setState(() => _error = 'Could not create your account. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Registers the new account with the backend, then re-reads the profile.
  ///
  /// Returns whether the backend accepted it. The re-read matters: if the
  /// backend had to fill in a missing trial, that grant only exists
  /// server-side, and without pulling it back the student would sit in front of
  /// a paywall for a trial they actually hold.
  Future<bool> _announceSignup(
    ApiClient api,
    SessionController session,
    Map<String, dynamic> signup,
  ) async {
    try {
      await api.post('/users/on-signup', signup);
      await session.refreshProfile();
      return true;
    } catch (_) {
      // Offline, or the backend is asleep. On the normal path the trial was
      // already written with the profile, so this only costs the welcome
      // message; on the recovery path the caller needs to know it failed.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
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
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Start free for 3 days', style: text.headlineMedium),
                      const SizedBox(height: Tokens.s2),
                      Text(
                        'Full access to every subject, past question and mock '
                        'exam. No card needed.',
                        style: text.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: Tokens.s6),

                      if (_error != null) ...[
                        MessageBanner(message: _error!),
                        const SizedBox(height: Tokens.s5),
                      ],

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _firstName,
                              enabled: !_busy,
                              decoration: const InputDecoration(
                                labelText: 'First name',
                              ),
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.givenName],
                              validator: (v) =>
                                  Validators.required(v, 'first name'),
                            ),
                          ),
                          const SizedBox(width: Tokens.s3),
                          Expanded(
                            child: TextFormField(
                              controller: _lastName,
                              enabled: !_busy,
                              decoration: const InputDecoration(
                                labelText: 'Last name',
                              ),
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.familyName],
                              validator: (v) =>
                                  Validators.required(v, 'last name'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Tokens.s4),

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
                        autofillHints: const [AutofillHints.email],
                        validator: Validators.email,
                      ),
                      const SizedBox(height: Tokens.s4),

                      TextFormField(
                        controller: _phone,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Phone number',
                          prefixIcon: Icon(Icons.phone_outlined),
                          hintText: '0801 234 5678',
                        ),
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d+\s-]')),
                        ],
                        validator: Validators.phone,
                      ),
                      const SizedBox(height: Tokens.s4),

                      DropdownButtonFormField<String>(
                        initialValue: _targetExam,
                        decoration: const InputDecoration(
                          labelText: 'Target exam',
                          prefixIcon: Icon(Icons.school_outlined),
                        ),
                        items: [
                          for (final exam in _targetExams)
                            DropdownMenuItem(value: exam, child: Text(exam)),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(
                                  () => _targetExam = v ?? _targetExams.first,
                                ),
                      ),
                      const SizedBox(height: Tokens.s4),

                      DropdownButtonFormField<String>(
                        initialValue: _state,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'State',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        items: [
                          for (final state in _nigerianStates)
                            DropdownMenuItem(value: state, child: Text(state)),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _state = v ?? 'Lagos'),
                      ),
                      const SizedBox(height: Tokens.s4),

                      TextFormField(
                        controller: _password,
                        enabled: !_busy,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          helperText:
                              'At least ${Validators.minPasswordLength} characters',
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
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        validator: Validators.password,
                      ),
                      const SizedBox(height: Tokens.s4),

                      TextFormField(
                        controller: _confirm,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        validator: (v) =>
                            Validators.confirmPassword(v, _password.text),
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
                            : const Text('Create my account'),
                      ),
                      const SizedBox(height: Tokens.s4),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account?',
                            style: text.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          TextButton(
                            onPressed:
                                _busy ? null : () => Navigator.of(context).pop(),
                            child: const Text('Sign in'),
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
