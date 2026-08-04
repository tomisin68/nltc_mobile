import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../domain/models/access_state.dart';
import '../core/state/dashboard_controller.dart';
import '../core/theme/app_palette.dart';

/// The strip of access warnings that sits above every dashboard view.
///
/// Port of the three `.dh-trial` banners in `src/pages/DashboardPage.jsx`. Only
/// one can ever apply at a time — the conditions are mutually exclusive by
/// construction, and they are ordered here the same way the web orders them.
class AccessBanners extends StatelessWidget {
  const AccessBanners({
    required this.access,
    required this.view,
    required this.viewIsFree,
    super.key,
  });

  final AccessState access;
  final DashboardView view;

  /// Whether the current view stays reachable while locked — a locked student on
  /// one of those needs the persistent banner explaining why the rest is gone.
  final bool viewIsFree;

  static final _dateFormat = DateFormat('d MMMM y', 'en_NG');

  @override
  Widget build(BuildContext context) {
    final locked = access.isLocked;

    // 1. Free trial running out.
    if (access.isOnTrial && access.trialDaysLeft <= 3) {
      final lastDay = access.trialDaysLeft <= 1;
      return _Banner(
        icon: Icons.hourglass_bottom_rounded,
        text: lastDay
            ? 'Free trial: Last day!'
            : 'Free trial: ${access.trialDaysLeft} days left',
        actionLabel: 'Upgrade',
        urgent: lastDay,
      );
    }

    // 2. A paid grant about to lapse — warn before the lock lands.
    final daysLeft = access.daysLeft;
    if (!locked && !access.isOnTrial && daysLeft != null && daysLeft <= 7) {
      return _Banner(
        icon: Icons.warning_amber_rounded,
        text: daysLeft == 0
            ? 'Your payment expires today — renew to keep your access.'
            : 'Your payment expires in $daysLeft '
                '${daysLeft == 1 ? 'day' : 'days'} — renew to keep your access.',
        actionLabel: 'Renew',
        urgent: daysLeft <= 1,
      );
    }

    // 3. Locked, on one of the views that stays reachable.
    if (locked && viewIsFree) {
      final expiresAt = access.expiresAt;
      final expired = access.reason == AccessReason.expired;
      return _Banner(
        icon: Icons.lock_rounded,
        text: expired
            ? 'Your payment expired'
                '${expiresAt == null ? '' : ' on ${_dateFormat.format(expiresAt)}'}'
                ' — lessons, CBT and live classes are locked.'
            : 'Your account is not active — lessons, CBT and live classes are '
                'locked.',
        // Already on Settings? The button would only point at the page they are
        // reading, so it is dropped rather than shown as a no-op.
        actionLabel: view == DashboardView.settings
            ? null
            : (expired ? 'Renew' : 'Pay Now'),
        urgent: true,
      );
    }

    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.urgent,
    this.actionLabel,
  });

  final IconData icon;
  final String text;

  /// `.dh-trial.last-day` — red rather than blue, for the final day and the lock.
  final bool urgent;

  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final background = urgent
        ? (isDark ? scheme.errorContainer.withValues(alpha: 0.25) : const Color(0xFFFFF5F5))
        : (isDark ? scheme.surfaceContainerLow : BlueprintPalette.b50);
    final borderColor = urgent
        ? (isDark ? scheme.error.withValues(alpha: 0.5) : const Color(0xFFFCA5A5))
        : (isDark ? scheme.outlineVariant : BlueprintPalette.b200);
    final iconColor = urgent
        ? scheme.error
        : (isDark ? scheme.primary : BlueprintPalette.b600);

    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s3),
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s4, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(Tokens.rMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.4,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: Tokens.s2),
            FilledButton(
              onPressed: () => context
                  .read<DashboardController>()
                  .select(DashboardView.settings),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
