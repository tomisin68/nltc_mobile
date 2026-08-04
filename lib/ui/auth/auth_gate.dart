import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/brand_mark.dart';
import '../shell/app_shell.dart';
import 'sign_in_screen.dart';

/// Chooses the root screen from the session state.
///
/// This is the app's only routing decision that isn't a push: sign-in and
/// sign-up push on top of whatever the gate has decided, and when Firebase
/// reports a new auth state the gate swaps the route underneath them.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final status =
        context.select<SessionController, SessionStatus>((s) => s.status);

    return AnimatedSwitcher(
      duration: Motion.base,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      child: switch (status) {
        SessionStatus.unknown => const _SplashScreen(key: ValueKey('splash')),
        SessionStatus.signedOut => const SignInScreen(key: ValueKey('signIn')),
        SessionStatus.signedIn => const AppShell(key: ValueKey('home')),
      },
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
              const BrandMark(size: 72),
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
