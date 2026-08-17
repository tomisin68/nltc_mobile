import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/brand_mark.dart';
import '../shell/app_shell.dart';
import 'sign_in_screen.dart';
import 'verify_email_screen.dart';

/// Chooses the root screen from the session state.
///
/// This is the app's only routing decision that isn't a push: sign-in and
/// sign-up push on top of whatever the gate has decided, and when Firebase
/// reports a new auth state the gate swaps the route underneath them.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.select<SessionController, SessionStatus>(
      (s) => s.status,
    );
    // Read separately so a change in either one rebuilds the gate — verifying
    // has to swap the code screen for the app without a restart.
    final mustVerify = context.select<SessionController, bool>(
      (s) => s.mustVerifyEmail,
    );

    return AnimatedSwitcher(
      duration: Motion.base,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      child: switch (status) {
        SessionStatus.unknown => const _SplashScreen(key: ValueKey('splash')),
        SessionStatus.signedOut => const SignInScreen(key: ValueKey('signIn')),
        // Email verification is a requirement, so it stands *in place of* the
        // app rather than on top of it. Putting it here rather than in the
        // sign-in handler is what reaches the students already signed in on a
        // device: they never touch a login form again, so a check that only
        // ran there would never run for them.
        SessionStatus.signedIn when mustVerify => const _VerifyEmailRoot(
          key: ValueKey('verify'),
        ),
        SessionStatus.signedIn => const AppShell(key: ValueKey('home')),
      },
    );
  }
}

/// The code screen as a root route: no back button, and no app behind it.
class _VerifyEmailRoot extends StatelessWidget {
  const _VerifyEmailRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    return VerifyEmailScreen(
      email: session.profile?.email ?? session.account?.email ?? '',
      mandatory: true,
    );
  }
}

/// Shown for the frame or two before Firebase reports who is signed in.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrandMark(height: 104),
          const SizedBox(height: Tokens.s8),
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    ),
  );
}
