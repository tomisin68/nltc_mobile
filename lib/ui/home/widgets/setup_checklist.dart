import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/access_state.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/live_session.dart';
import '../../core/state/dashboard_controller.dart';
import '../../core/theme/app_palette.dart';

/// The "get set up" list a new student is walked through.
///
/// Port of `SetupChecklist`. It disappears entirely once every item is done —
/// a checklist of ticks is clutter, and the point of this card is the things that
/// are still outstanding.
class SetupChecklist extends StatelessWidget {
  const SetupChecklist({
    super.key,
    required this.profile,
    required this.access,
  });

  final AppUser profile;
  final AccessState access;

  List<_SetupItem> _items() {
    final isPhysical = profile.studentMode == 'physical';
    final isJunior = profile.isJunior;
    // A student inside their free trial already has everything, so paying is a
    // reminder rather than a blocker — the copy and the urgency both change.
    final onTrial = access.reason == AccessReason.trial;
    final daysLeft = access.trialDaysLeft;
    final trialNote = 'Free trial ends in $daysLeft day'
        '${daysLeft == 1 ? '' : 's'} — pay to keep your access';

    return [
      _SetupItem(
        id: 'profile',
        icon: Icons.badge_rounded,
        tint: const Color(0xFF2563EB),
        label: 'Complete your profile',
        description: 'Add your phone number, state and target exam',
        done: (profile.firstName?.isNotEmpty ?? false) &&
            (profile.lastName?.isNotEmpty ?? false) &&
            (profile.phone?.isNotEmpty ?? false),
        view: DashboardView.profile,
        action: 'Go Now',
      ),
      if (isPhysical)
        _SetupItem(
          id: 'lesson_fee',
          icon: Icons.credit_card_rounded,
          tint: const Color(0xFFDC2626),
          label: 'Pay your lesson fee',
          description: onTrial
              ? trialNote
              : 'Monthly fee to access all lessons and features',
          done: profile.lessonFeePaid,
          view: DashboardView.settings,
          action: 'Pay Now',
          urgent: !profile.lessonFeePaid && !onTrial,
        ),
      if (!isJunior && !isPhysical && (profile.plan ?? 'free') == 'free')
        _SetupItem(
          id: 'upgrade',
          icon: Icons.rocket_launch_rounded,
          tint: const Color(0xFF7C3AED),
          label: 'Upgrade to Pro',
          description:
              onTrial ? trialNote : 'Unlock all lessons, live classes, and more',
          done: false,
          view: DashboardView.settings,
          action: 'Upgrade',
        ),
      _SetupItem(
        id: 'first_cbt',
        icon: isJunior ? Icons.school_rounded : Icons.laptop_mac_rounded,
        tint: const Color(0xFF059669),
        label: isJunior
            ? 'Take your first BECE practice test'
            : 'Take your first CBT session',
        description: 'Test your knowledge and start earning XP',
        done: profile.cbtCount > 0,
        view: isJunior ? DashboardView.bece : DashboardView.cbt,
        action: 'Start Now',
      ),
      if (isJunior)
        _SetupItem(
          id: 'join_live',
          icon: Icons.sensors_rounded,
          tint: const Color(0xFF7C3AED),
          label: 'Join a live class',
          description: 'Attend a session to earn 50 XP',
          done: profile.xp >= 50,
          view: DashboardView.live,
          action: 'Join Now',
        )
      else
        _SetupItem(
          id: 'lessons',
          icon: Icons.play_circle_rounded,
          tint: const Color(0xFF0284C7),
          label: 'Watch a video lesson',
          description: 'Earn 20 XP for every lesson you complete',
          done: profile.xp >= 20,
          view: DashboardView.lessons,
          action: 'Watch Now',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _items();
    final pending = items.where((i) => !i.done).toList();
    if (pending.isEmpty) return const SizedBox.shrink();

    final done = items.length - pending.length;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Tokens.s4, 13, Tokens.s4, 11),
            child: Row(
              children: [
                Icon(
                  Icons.checklist_rounded,
                  size: 15,
                  color: BlueprintPalette.warning,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Your Setup Checklist',
                    style: GoogleFonts.fraunces(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  '$done / ${items.length} complete',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (final item in pending)
            _SetupRow(item: item, isLast: item == pending.last),
        ],
      ),
    );
  }
}

class _SetupItem {
  const _SetupItem({
    required this.id,
    required this.icon,
    required this.tint,
    required this.label,
    required this.description,
    required this.done,
    required this.view,
    required this.action,
    this.urgent = false,
  });

  final String id;
  final IconData icon;
  final Color tint;
  final String label;
  final String description;
  final bool done;
  final DashboardView view;
  final String action;

  /// Draws the row in the error tone — an unpaid fee on a live account.
  final bool urgent;
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({required this.item, required this.isLast});

  final _SetupItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s4,
        vertical: Tokens.s3,
      ),
      decoration: BoxDecoration(
        color: item.urgent
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : null,
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: item.tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Tokens.rXs),
            ),
            alignment: Alignment.center,
            child: Icon(item.icon, size: 16, color: item.tint),
          ),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  item.description,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Tokens.s2),
          FilledButton(
            onPressed: () =>
                context.read<DashboardController>().select(item.view),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              backgroundColor: item.urgent ? scheme.error : null,
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Text(item.action),
          ),
        ],
      ),
    );
  }
}

/// The fee alert for a centre student who hasn't paid and isn't on trial.
///
/// Port of `PaymentAlert`. It says plainly that paying at the centre counts,
/// because the commonest support question is a student who has already paid cash
/// and is being told their account is pending.
class PaymentAlert extends StatelessWidget {
  const PaymentAlert({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(Tokens.s4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 22,
                  color: scheme.error,
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monthly Lesson Fee Required',
                        style: GoogleFonts.fraunces(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Your account is pending activation. Pay your monthly '
                        'lesson fee to unlock video lessons, CBT practice, live '
                        'classes, and all other features.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Tokens.s3),
                      FilledButton.icon(
                        onPressed: () => context
                            .read<DashboardController>()
                            .select(DashboardView.settings),
                        icon: const Icon(Icons.credit_card_rounded, size: 16),
                        label: const Text('Pay Now'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s4,
              vertical: Tokens.s2,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Already paid at the centre? Your admin will activate your '
                    'account — no need to pay again.',
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "LIVE NOW" strip — the most time-sensitive thing that can be on the page.
class LiveNowBanner extends StatelessWidget {
  const LiveNowBanner({
    super.key,
    required this.session,
    required this.onJoin,
  });

  final LiveSession session;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s4,
        vertical: Tokens.s3,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Row(
        children: [
          const _PulsingDot(),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIVE NOW: ${session.title}',
                  style: GoogleFonts.fraunces(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [
                    if (session.subject != null) session.subject,
                    '${session.watching} watching',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Tokens.s2),
          FilledButton.icon(
            onPressed: onJoin,
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

/// The pulsing red dot beside "LIVE NOW" — `@keyframes pulse-dot`.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.35).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
      ),
    );
  }
}
