import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../data/services/prefs_service.dart';
import '../../auth/verify_email_screen.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/app_palette.dart';

/// Asks a student who skipped verification to finish it.
///
/// Verification is a nudge on this platform, not a gate, so this is the whole
/// enforcement: it can be dismissed, and it comes back after
/// [PrefsService.verifyNagGap]. The stake is worth repeating — an unverified
/// address cannot receive a password reset, so the account is one forgotten
/// password away from being unrecoverable.
///
/// Renders nothing when there is nothing to ask for: a verified student, one
/// who dismissed it recently, or an account with no address to verify.
class VerifyEmailBanner extends StatefulWidget {
  const VerifyEmailBanner({super.key});

  @override
  State<VerifyEmailBanner> createState() => _VerifyEmailBannerState();
}

class _VerifyEmailBannerState extends State<VerifyEmailBanner> {
  /// Dismissed in this session. Held separately from the stored timestamp so
  /// the banner disappears on the tap rather than after the write lands.
  bool _dismissed = false;

  Future<void> _openVerification(String email) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        // The tap is the request, so the screen mails a code as it opens.
        builder: (_) => VerifyEmailScreen(email: email),
      ),
    );
    // Nothing to do with the result: a success has already been written to the
    // session, which rebuilds this out of existence.
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    await context.read<PrefsService>().dismissVerifyBanner();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final email = session.profile?.email ?? session.account?.email;

    if (_dismissed ||
        session.emailVerified ||
        email == null ||
        email.isEmpty ||
        !context.read<PrefsService>().shouldNagAboutVerifying) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    // The gap below is the banner's own, so the dashboard is not left with a
    // double space on every screen where this renders nothing.
    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s3),
      padding: const EdgeInsets.fromLTRB(
        Tokens.s4,
        Tokens.s3,
        Tokens.s2,
        Tokens.s3,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mark_email_unread_outlined, size: 22, color: scheme.primary),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verify your email',
                  style: GoogleFonts.fraunces(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Confirm $email so you can reset your password if you ever '
                  'lose it, and so we can reach you about your account.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Tokens.s3),
                FilledButton.icon(
                  onPressed: () => _openVerification(email),
                  icon: const Icon(Icons.verified_outlined, size: 16),
                  label: const Text('Verify now'),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _dismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Remind me later',
            visualDensity: VisualDensity.compact,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
