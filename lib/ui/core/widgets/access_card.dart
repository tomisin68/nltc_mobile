import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/access_state.dart';
import '../theme/app_palette.dart';

/// What the student's account currently entitles them to.
///
/// Everything here comes from [AccessState], which is the same evaluation the
/// website runs — so a student who is locked out on one is locked out on both.
class AccessCard extends StatelessWidget {
  const AccessCard({super.key, required this.access});

  final AccessState access;

  static final _dateFormat = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (!access.known) {
      return _Panel(
        background: scheme.surfaceContainer,
        border: scheme.outlineVariant,
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: Tokens.s4),
            Text(
              'Checking your access…',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (!access.active) return _LockedPanel(access: access);

    final (title, detail, icon) = switch (access.reason) {
      AccessReason.staff => (
          'Staff account',
          'Full access — student fees do not apply to you.',
          Icons.verified_user_outlined,
        ),
      AccessReason.trial => (
          access.trialDaysLeft == 1
              ? 'Free trial — 1 day left'
              : 'Free trial — ${access.trialDaysLeft} days left',
          access.expiresAt == null
              ? 'Enjoy full access while your trial runs.'
              : 'Your trial ends on ${_dateFormat.format(access.expiresAt!)}.',
          Icons.hourglass_bottom_outlined,
        ),
      AccessReason.lessonFee => (
          'Lesson fee active',
          access.expiresAt == null
              ? 'Your centre has you covered.'
              : 'Covered until ${_dateFormat.format(access.expiresAt!)}.',
          Icons.school_outlined,
        ),
      AccessReason.plan => (
          'Subscription active',
          access.expiresAt == null
              ? 'Full access to every subject.'
              : 'Renews on ${_dateFormat.format(access.expiresAt!)}.',
          Icons.workspace_premium_outlined,
        ),
      _ => (
          'Account active',
          'Full access to every subject, past question and mock exam.',
          Icons.check_circle_outline,
        ),
    };

    return _Panel(
      background: scheme.tertiaryContainer,
      border: scheme.tertiary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.onTertiaryContainer),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleMedium
                      ?.copyWith(color: scheme.onTertiaryContainer),
                ),
                const SizedBox(height: Tokens.s1),
                Text(
                  detail,
                  style: text.bodyMedium
                      ?.copyWith(color: scheme.onTertiaryContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The paywall.
///
/// Payment is taken on the website, so the only honest call to action is to say
/// where to go and with which email — an in-app button that can't actually take
/// money would be worse than none.
class _LockedPanel extends StatelessWidget {
  const _LockedPanel({required this.access});

  final AccessState access;

  Future<void> _explain(BuildContext context) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Activating your account'),
          content: const Text(
            'Payments are taken on nltc.com.ng. Sign in there with the same '
            'email you use here, choose a plan, and this app unlocks by itself '
            'within a few seconds — no need to sign out or reinstall.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return _Panel(
      background: scheme.errorContainer,
      border: scheme.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, color: scheme.onErrorContainer),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Text(
                  access.headline,
                  style:
                      text.titleMedium?.copyWith(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s2),
          Text(
            access.subline,
            style: text.bodyMedium?.copyWith(color: scheme.onErrorContainer),
          ),
          if (access.expiresAt != null) ...[
            const SizedBox(height: Tokens.s2),
            Text(
              'Access ran out on '
              '${AccessCard._dateFormat.format(access.expiresAt!)}.',
              style: text.bodySmall?.copyWith(color: scheme.onErrorContainer),
            ),
          ],
          const SizedBox(height: Tokens.s3),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: () => _explain(context),
              child: const Text('How do I activate?'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    required this.background,
    required this.border,
  });

  final Widget child;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Tokens.s5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(Tokens.rLg),
          border: Border.all(color: border.withValues(alpha: 0.35)),
        ),
        child: child,
      );
}
