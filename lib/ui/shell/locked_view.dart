import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../domain/models/access_state.dart';
import '../core/state/dashboard_controller.dart';
import '../core/theme/app_palette.dart';

/// What a locked student sees in place of a gated view.
///
/// Port of `LockedView` / `lockedCopy()` in `src/pages/DashboardPage.jsx`. The
/// copy branches on *why* access ended, because "your payment expired" and "your
/// free trial ended" need different answers — and a student who paid cash at
/// their centre needs telling not to pay twice.
class LockedView extends StatelessWidget {
  const LockedView({super.key, required this.access});

  final AccessState access;

  static final _dateFormat = DateFormat('d MMMM y', 'en_NG');

  ({IconData icon, String title, String body, IconData ctaIcon, String cta})
      get _copy {
    switch (access.reason) {
      case AccessReason.expired:
        final on = access.expiresAt;
        return (
          icon: Icons.event_busy_rounded,
          title: 'Your Access Has Expired',
          body: on == null
              ? 'Your monthly payment has run out. Renew to unlock video '
                  'lessons, CBT practice, live classes, leaderboard and '
                  'everything else.'
              : 'Your monthly payment ran out on ${_dateFormat.format(on)}. '
                  'Renew to unlock video lessons, CBT practice, live classes, '
                  'leaderboard and everything else.',
          ctaIcon: Icons.sync_rounded,
          cta: 'Renew Now',
        );
      case AccessReason.trialEnded:
        return (
          icon: Icons.hourglass_disabled_rounded,
          title: 'Your Free Trial Has Ended',
          body: 'Your free trial is over. Pay your monthly fee to keep '
              'learning — unlock video lessons, CBT practice, live classes, '
              'leaderboard, and more.',
          ctaIcon: Icons.star_rounded,
          cta: 'See My Fee',
        );
      default:
        return (
          icon: Icons.lock_rounded,
          title: 'Access Restricted',
          body: 'Pay your monthly fee to unlock everything — video lessons, '
              'CBT practice, live classes, leaderboard, and more.',
          ctaIcon: Icons.credit_card_rounded,
          cta: 'Pay Now',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final copy = _copy;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Tokens.s6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? scheme.surfaceContainerLow
                  : BlueprintPalette.white,
              borderRadius: BorderRadius.circular(Tokens.rLg),
              border: Border(
                // `.locked-card` is capped with a 4px brand rule.
                top: BorderSide(color: scheme.primary, width: 4),
              ),
              boxShadow: [
                BoxShadow(
                  color: BlueprintPalette.b900.withValues(alpha: 0.10),
                  blurRadius: 40,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.s8,
                vertical: Tokens.s12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? scheme.primaryContainer
                          : BlueprintPalette.b100,
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Icon(copy.icon, size: 30, color: scheme.primary),
                  ),
                  const SizedBox(height: Tokens.s5),
                  Text(
                    copy.title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.fraunces(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    copy.body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.7,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Tokens.s6),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context
                          .read<DashboardController>()
                          .select(DashboardView.settings),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: Icon(copy.ctaIcon, size: 18),
                      label: Text(copy.cta),
                    ),
                  ),
                  const SizedBox(height: Tokens.s4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: Tokens.s3,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? scheme.surfaceContainerHigh
                          : const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(Tokens.rSm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: isDark
                              ? scheme.primary
                              : const Color(0xFF0369A1),
                        ),
                        const SizedBox(width: Tokens.s2),
                        Expanded(
                          child: Text(
                            'Already paid at your centre? Your admin will '
                            'activate your account shortly. You do not need to '
                            'pay again.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: isDark
                                  ? scheme.onSurfaceVariant
                                  : const Color(0xFF0369A1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
