import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/email_verification_repository.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/message_banner.dart';

/// The 6-digit code screen.
///
/// Port of the `screen === 'otp'` branch of `src/pages/AuthPage.jsx`, and used
/// in two shapes.
///
/// **[mandatory]** is the one that matters: verification is a requirement for
/// students, and [AuthGate] shows this *in place of* the app until it is done.
/// There is no back, no "later", and nothing behind it — because there is
/// nothing behind it to go back to. The one way off it without a code is
/// signing out, which a student who mistyped their address at signup needs:
/// their code can never arrive, and sealing them onto a screen that cannot be
/// satisfied would be the worst outcome of this whole change.
///
/// Pushed without [mandatory] it is the old dismissible sheet, still reached
/// from the profile row by staff — who are exempt from the gate and may verify
/// voluntarily.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.email,
    this.mandatory = false,
  });

  /// Shown so the student can see which address to go and check — and spot the
  /// typo that is the real reason the mail never came.
  final String email;

  /// Standing in for the app rather than sitting on top of it.
  final bool mandatory;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  /// Seconds until the resend button comes back. Matches the web's 60.
  static const _resendCooldown = 60;

  int _cooldown = 0;
  Timer? _ticker;

  bool _busy = false;
  bool _sending = false;
  String? _error;

  /// Set when the code itself is finished rather than merely wrong, so the
  /// screen can point at the resend button instead of the keypad.
  bool _needsNewCode = false;

  @override
  void initState() {
    super.initState();
    // Both routes here — straight from signup, and the profile's "Verify" —
    // are a request for a code, so one goes out as the screen opens. Deferred
    // a frame so the first paint is the screen rather than a spinner.
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _cooldown = _resendCooldown);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _send({bool resend = false}) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    final repository = context.read<EmailVerificationRepository>();
    try {
      if (resend) {
        await repository.resend();
      } else {
        await repository.send();
      }
      if (!mounted) return;
      // A resend replaces the code, so whatever is in the field is now wrong.
      if (resend) _code.clear();
      _needsNewCode = false;
      _startCooldown();
      showToast(
        'New code sent — check your inbox',
        variant: ToastVariant.success,
      );
    } on VerificationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (_busy || code.length != 6) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _error = null;
    });

    final repository = context.read<EmailVerificationRepository>();
    final session = context.read<SessionController>();
    final navigator = Navigator.of(context);

    try {
      await repository.verify(code);
      // Told before the screen closes, so nothing behind it can rebuild still
      // believing this student is unverified.
      await session.markEmailVerified();
      if (!mounted) return;
      showToast('Email verified', variant: ToastVariant.success);
      // As the gate, this screen *is* the route — `markEmailVerified` has
      // already flipped `mustVerifyEmail`, so AuthGate swaps the app in
      // underneath. Popping would take the app with it.
      if (!widget.mandatory) navigator.pop(true);
    } on VerificationFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _needsNewCode = !e.retryable;
        _busy = false;
      });
      // A spent code cannot be fixed by editing it; a wrong one can.
      if (_needsNewCode) {
        _code.clear();
      } else {
        _codeFocus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final canResend = _cooldown <= 0 && !_sending;

    return PopScope(
      // As the gate there is nothing behind this to pop to, and the hardware
      // back button must not look like a way around it.
      canPop: !widget.mandatory,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Verify your email'),
          automaticallyImplyLeading: !widget.mandatory,
        ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.mark_email_read_outlined,
                          size: 30,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: Tokens.s5),

                    Text(
                      'Check your inbox',
                      style: text.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Tokens.s2),
                    Text.rich(
                      TextSpan(
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        children: [
                          const TextSpan(text: 'We sent a 6-digit code to '),
                          TextSpan(
                            text: widget.email,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text:
                                '. It expires in '
                                '${EmailVerificationRepository.codeLifetime.inMinutes} '
                                'minutes.',
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Tokens.s6),

                    if (_error != null) ...[
                      MessageBanner(message: _error!),
                      const SizedBox(height: Tokens.s5),
                    ],

                    TextField(
                      controller: _code,
                      focusNode: _codeFocus,
                      enabled: !_busy,
                      autofocus: true,
                      // `oneTimeCode` is what lets Android's SMS/mail autofill and
                      // iOS's keyboard strip offer the code without retyping it.
                      autofillHints: const [AutofillHints.oneTimeCode],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      style: text.headlineMedium?.copyWith(
                        letterSpacing: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Verification code',
                        hintText: '000000',
                        counterText: '',
                      ),
                      onChanged: (v) {
                        setState(() {});
                        // Submitting the moment the sixth digit lands saves a tap
                        // and matches what every OTP field on a phone does.
                        if (v.length == 6) _verify();
                      },
                      onSubmitted: (_) => _verify(),
                    ),
                    const SizedBox(height: Tokens.s5),

                    FilledButton(
                      onPressed: _busy || _code.text.length < 6
                          ? null
                          : _verify,
                      child: _busy
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: scheme.onPrimary,
                              ),
                            )
                          : const Text('Verify email'),
                    ),
                    const SizedBox(height: Tokens.s4),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Didn't get it?",
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        TextButton(
                          onPressed: canResend
                              ? () => _send(resend: true)
                              : null,
                          child: Text(
                            _cooldown > 0
                                ? 'Resend in ${_cooldown}s'
                                : 'Resend code',
                          ),
                        ),
                      ],
                    ),

                    Text(
                      'Check your spam folder too — the code arrives from '
                      'no-reply@nltc.com.ng.',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Tokens.s6),

                    // As the gate, the only way off without a code — for the
                    // student who mistyped their address and so can never
                    // receive one. Otherwise, the old snooze.
                    TextButton(
                      onPressed: _busy
                          ? null
                          : widget.mandatory
                          ? _signOut
                          : () => Navigator.of(context).pop(false),
                      child: Text(
                        widget.mandatory
                            ? 'Wrong address? Sign out'
                            : "I'll do this later",
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

  /// Leaves the gate the only way it can be left without a code.
  ///
  /// Signing out drops the session, so AuthGate falls back to the sign-in
  /// screen. Support can then correct the address on the account.
  Future<void> _signOut() async {
    final session = context.read<SessionController>();
    await session.signOut();
    if (!mounted) return;
    showToast(
      'Signed out. You will need to verify your email to continue.',
      variant: ToastVariant.info,
    );
  }
}
