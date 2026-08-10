import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../data/services/prefs_service.dart';
import '../../domain/models/access_state.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/gamification.dart';
import '../../domain/models/wrapped_stats.dart';
import '../core/state/dashboard_badge_controller.dart';
import '../core/state/dashboard_controller.dart';
import '../core/state/notification_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/brand_mark.dart';
import '../core/widgets/ruled_paper.dart';
import '../support/support_sheet.dart';
import '../wrapped/wrapped_screen.dart';

/// The student sidebar — a direct port of the web app's "exercise book" spine
/// (`ds-*` classes in `src/components/layout/SidebarStudent.css`).
///
/// Paper-white with ruled lines and a margin rule down the left, unit-numbered
/// sections, and a highlighter sweep behind the active link. On the web this is
/// a fixed rail on desktop that slides in as a drawer under 768px; the phone
/// only ever sees the drawer, so that is all this builds.
class DashboardSidebar extends StatelessWidget {
  const DashboardSidebar({super.key});

  /// `--sidebar-w`. Held to the web value so the two read as one product, but
  /// capped against the viewport for small phones.
  static const _width = 248.0;

  /// Views that stay reachable when an account is locked — `FREE_VIEWS` on the
  /// web. Everything else shows a padlock.
  static const _freeViews = {
    DashboardView.home,
    DashboardView.profile,
    DashboardView.settings,
    DashboardView.blog,
  };

  /// Junior track. Matches `isJSS` everywhere on the web — the string list is
  /// the contract, not a `level` field, because that is what admins actually set.
  static bool isJuniorStudent(AppUser? user) =>
      const {'BECE (JSS)', 'Junior WAEC'}.contains(user?.targetExam);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final profile = session.profile;
    final access = session.access;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final width = _width.clamp(0.0, MediaQuery.sizeOf(context).width * 0.86);
    final isJunior = isJuniorStudent(profile);
    final locked = access.isLocked;

    return Drawer(
      width: width,
      backgroundColor: isDark
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : BlueprintPalette.white,
      shape: Border(
        right: BorderSide(
          color: isDark
              ? Theme.of(context).colorScheme.outlineVariant
              : BlueprintPalette.b100,
          width: 2,
        ),
      ),
      child: CustomPaint(
        // The ruled paper and the margin rule are painted rather than tiled from
        // an asset so they stay crisp at any density and follow the theme.
        painter: RuledPaperPainter(isDark: isDark, marginRuleAt: 14),
        child: SafeArea(
          child: Column(
            children: [
              const _Brand(),
              _StudentIdCard(
                profile: profile,
                access: access,
                isJunior: isJunior,
                onTap: () => _go(context, DashboardView.profile),
              ),
              _XpBlock(xp: profile?.xp ?? 0),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                  children: isJunior
                      ? _juniorNav(context, locked)
                      : _seniorNav(context, locked),
                ),
              ),
              _UpgradeCard(profile: profile),
              const _SignOutRow(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Nav ───────────────────────────────────────────────────────────────────

  List<Widget> _juniorNav(BuildContext context, bool locked) => [
        const _NavSection(number: '01', label: 'Study'),
        _link(context, DashboardView.home, Icons.dashboard_rounded, 'Dashboard',
            locked),
        _link(context, DashboardView.bece, Icons.school_rounded,
            'BECE Practice', locked),
        _link(context, DashboardView.notes, Icons.menu_book_rounded,
            'Study Notes', locked),
        const _NavSection(number: '02', label: 'Compete & Connect'),
        _link(context, DashboardView.live, Icons.sensors_rounded,
            'Live Classes', locked,
            showLiveDot: true),
        _link(context, DashboardView.leaderboard, Icons.emoji_events_rounded,
            'Leaderboard', locked),
        _link(context, DashboardView.chat, Icons.chat_bubble_rounded, 'Messages',
            locked,
            badge: _Badge.chat),
        _link(context, DashboardView.announcements, Icons.campaign_rounded,
            'Announcements', locked,
            badge: _Badge.notifications),
        _link(context, DashboardView.blog, Icons.article_rounded, 'Blog',
            locked),
        const _NavSection(number: '03', label: 'My Account'),
        const _WrappedLink(),
        _link(context, DashboardView.profile, Icons.badge_rounded, 'My Profile',
            locked),
        _link(context, DashboardView.settings, Icons.settings_rounded,
            'Settings', locked),
        const _SupportLink(),
      ];

  List<Widget> _seniorNav(BuildContext context, bool locked) => [
        const _NavSection(number: '01', label: 'Study'),
        _link(context, DashboardView.home, Icons.dashboard_rounded, 'Dashboard',
            locked),
        _link(context, DashboardView.lessons, Icons.play_circle_rounded,
            'Video Lessons', locked),
        _link(context, DashboardView.cbt, Icons.laptop_mac_rounded,
            'CBT Practice', locked),
        _link(context, DashboardView.quickTest, Icons.bolt_rounded,
            'Quick Tests', locked),
        _link(context, DashboardView.notes, Icons.menu_book_rounded,
            'Study Notes', locked),
        const _NavSection(number: '02', label: 'Compete & Connect'),
        _link(context, DashboardView.live, Icons.sensors_rounded,
            'Live Classes', locked,
            showLiveDot: true),
        _link(context, DashboardView.mockExams, Icons.description_rounded,
            'Mock Exams', locked),
        _link(context, DashboardView.leaderboard, Icons.emoji_events_rounded,
            'Leaderboard', locked),
        _link(context, DashboardView.chat, Icons.chat_bubble_rounded, 'Messages',
            locked,
            badge: _Badge.chat),
        _link(context, DashboardView.announcements, Icons.campaign_rounded,
            'Announcements', locked,
            badge: _Badge.notifications),
        _link(context, DashboardView.blog, Icons.article_rounded, 'Blog',
            locked),
        const _NavSection(number: '03', label: 'My Account'),
        const _WrappedLink(),
        _link(context, DashboardView.profile, Icons.badge_rounded, 'My Profile',
            locked),
        _link(context, DashboardView.settings, Icons.settings_rounded,
            'Settings', locked),
        const _SupportLink(),
      ];

  Widget _link(
    BuildContext context,
    DashboardView view,
    IconData icon,
    String label,
    bool accountLocked, {
    bool showLiveDot = false,
    _Badge? badge,
  }) =>
      _NavLink(
        view: view,
        icon: icon,
        label: label,
        locked: accountLocked && !_freeViews.contains(view),
        showLiveDot: showLiveDot,
        badge: badge,
        onTap: () => _go(context, view),
      );

  /// Navigating always closes the drawer — on a phone the drawer covers the view
  /// it just switched to, so leaving it open would hide the result of the tap.
  static void _go(BuildContext context, DashboardView view) {
    context.read<DashboardController>().select(view);
    Navigator.of(context).maybePop();
  }
}

/// Which counter a nav link displays, if any.
enum _Badge { chat, notifications }

// ─── Paper ───────────────────────────────────────────────────────────────────

/// A dashed hairline — the `1px dashed var(--border-2)` separators.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(double.infinity, 1),
        painter: _DashedLinePainter(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      );
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 3.0;
    const gap = 3.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

// ─── Brand ───────────────────────────────────────────────────────────────────

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          // `.ds-brand` — the 26px left inset clears the margin rule.
          padding: const EdgeInsets.only(left: 26, right: 20, top: 16, bottom: 13),
          child: const Align(
            alignment: Alignment.centerLeft,
            // The lockup carries the wordmark itself, so the rail shows the
            // logo alone the way `.ds-brand-img` does on the web.
            child: BrandMark(height: 46),
          ),
        ),
        const _DashedDivider(),
      ],
    );
  }
}

// ─── Student ID card ─────────────────────────────────────────────────────────

class _StudentIdCard extends StatelessWidget {
  const _StudentIdCard({
    required this.profile,
    required this.access,
    required this.isJunior,
    required this.onTap,
  });

  final AppUser? profile;
  final AccessState access;
  final bool isJunior;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      // `.ds-id` — 20px left keeps it clear of the margin rule.
      padding: const EdgeInsets.only(left: 20, right: 12, top: 12),
      child: Material(
        color: isDark ? scheme.surfaceContainerHigh : BlueprintPalette.b50,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.rMd),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.rMd),
              border: Border.all(
                color: isDark ? scheme.outlineVariant : BlueprintPalette.b100,
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                _Avatar(profile: profile),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        profile?.displayName ?? 'Student',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _PlanTag(
                        profile: profile,
                        access: access,
                        isJunior: isJunior,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile});

  final AppUser? profile;

  @override
  Widget build(BuildContext context) {
    // `avatarUrl`, not `photoUrl`: the picture a student uploads on the profile
    // screen lands in `profileImage`, and `photoURL` is only ever set for
    // Google sign-ins. Reading the raw field left every email/password account
    // — and everyone who had uploaded their own photo — on initials forever.
    // This is what the web sidebar shows too (`userData.profileImage`).
    final photo = profile?.avatarUrl;

    return Container(
      width: 36,
      height: 36,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BlueprintPalette.b600, BlueprintPalette.b400],
        ),
      ),
      alignment: Alignment.center,
      child: photo != null && photo.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: photo,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              // Cached to disk, so the student's own face is on the sidebar the
              // moment it opens rather than after a round trip on every launch.
              // Initials stand in while it loads, and stay if the URL is broken
              // or unreachable — Flutter's grey placeholder box never shows.
              placeholder: (_, _) => _initials(context),
              errorWidget: (_, _, _) => _initials(context),
            )
          : _initials(context),
    );
  }

  Widget _initials(BuildContext context) => Text(
        profile?.initials ?? '?',
        style: GoogleFonts.fraunces(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: BlueprintPalette.white,
          height: 1,
        ),
      );
}

/// The plan pill under the student's name.
///
/// Order matters and matches `Sidebar.jsx`: a junior badge wins outright, then a
/// paid centre fee, then Pro, then a running trial, then Free. Trial state is
/// read off the live [AccessState] rather than a cached profile flag, so the
/// pill cannot still read "Trial · 1d" the day after it ran out.
class _PlanTag extends StatelessWidget {
  const _PlanTag({
    required this.profile,
    required this.access,
    required this.isJunior,
  });

  final AppUser? profile;
  final AccessState access;
  final bool isJunior;

  @override
  Widget build(BuildContext context) {
    if (isJunior) {
      return const _Pill(
        icon: Icons.school_rounded,
        label: 'JSS Student',
        background: BlueprintPalette.b800,
        foreground: BlueprintPalette.white,
      );
    }

    final plan = profile?.plan ?? 'free';
    final isPhysical = profile?.studentMode == 'physical';
    final isPhysicalPaid = isPhysical && (profile?.lessonFeePaid ?? false);
    final onTrial = access.reason == AccessReason.trial;

    const proBackground = Color(0x241D6FF2); // rgba(29,111,242,.14)
    const proForeground = BlueprintPalette.b700;

    if (isPhysicalPaid) {
      return const _Pill(
        icon: Icons.check_circle_rounded,
        label: 'Paid',
        background: proBackground,
        foreground: proForeground,
      );
    }
    if (plan == 'pro') {
      return const _Pill(
        icon: Icons.local_fire_department_rounded,
        label: 'Pro',
        background: proBackground,
        foreground: proForeground,
      );
    }
    if (onTrial) {
      return _Pill(
        icon: Icons.card_giftcard_rounded,
        label: 'Trial · ${access.trialDaysLeft}d',
        background: proBackground,
        foreground: proForeground,
      );
    }
    return _Pill(
      label: 'Free',
      background: const Color(0x0F092A5E), // rgba(9,42,94,.06)
      foreground: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 10, color: foreground),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: foreground,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
}

// ─── XP block ────────────────────────────────────────────────────────────────

class _XpBlock extends StatelessWidget {
  const _XpBlock({required this.xp});

  final int xp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final level = Levels.forXp(xp);
    final progress = Levels.progressInLevel(xp);
    final nextXp = Levels.nextLevelXp(xp);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 26, right: 20, top: 12, bottom: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      Levels.nameForXp(xp),
                      // `.ds-xp-level` is set in Caveat — the handwritten note
                      // in the margin of the student's own exercise book.
                      style: GoogleFonts.caveat(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: isDark ? scheme.primary : BlueprintPalette.b600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${_thousands(xp)} XP',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: SizedBox(
                  height: 5,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: isDark
                              ? scheme.surfaceContainerHigh
                              : BlueprintPalette.b100,
                        ),
                      ),
                      // Animated so XP landing from a finished test reads as
                      // progress filling up rather than as a jump.
                      Positioned.fill(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: progress.clamp(0.0, 1.0)),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeInOutCubic,
                          builder: (context, value, _) =>
                              FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: value,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    BlueprintPalette.b600,
                                    BlueprintPalette.b400,
                                  ],
                                ),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(100)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Level $level · ${_thousands(nextXp)} XP to next',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
        const _DashedDivider(),
      ],
    );
  }

  static String _thousands(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]},',
      );
}

// ─── Nav section header ──────────────────────────────────────────────────────

class _NavSection extends StatelessWidget {
  const _NavSection({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 26, right: 16, top: 14, bottom: 5),
      child: Row(
        children: [
          Text(
            number,
            style: GoogleFonts.caveat(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1,
              color: BlueprintPalette.b400,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Container(height: 1, color: scheme.outlineVariant),
          ),
        ],
      ),
    );
  }
}

// ─── Nav link ────────────────────────────────────────────────────────────────

class _NavLink extends StatelessWidget {
  const _NavLink({
    required this.view,
    required this.icon,
    required this.label,
    required this.locked,
    required this.onTap,
    this.showLiveDot = false,
    this.badge,
  });

  final DashboardView view;
  final IconData icon;
  final String label;
  final bool locked;
  final VoidCallback onTap;
  final bool showLiveDot;
  final _Badge? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active =
        context.select<DashboardController, bool>((c) => c.view == view);

    final liveDot = showLiveDot &&
        !locked &&
        context.select<DashboardBadgeController, bool>((c) => c.liveActive);
    final count = locked ? 0 : _badgeCount(context);

    final iconColor = active
        ? BlueprintPalette.white
        : (isDark ? scheme.onSurfaceVariant : BlueprintPalette.text3);
    final iconBackground = active
        ? BlueprintPalette.b600
        : (isDark ? scheme.surfaceContainerHigh : BlueprintPalette.b50);

    return Opacity(
      // `.ds-link.sb-link-locked` — dimmed, but still tappable so the student
      // lands on the paywall and learns why, rather than on a dead button.
      opacity: locked ? 0.5 : 1,
      child: Stack(
        children: [
          // The active marker: a 3px pen tick in the margin.
          if (active)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  width: 3,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: BlueprintPalette.b500,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(3),
                      bottomRight: Radius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          InkWell(
            onTap: onTap,
            child: Container(
              // The web link is ~42px tall. Raised to the 48dp touch minimum
              // here: this is a finger target, not a cursor target.
              constraints:
                  const BoxConstraints(minHeight: Tokens.minTouchTarget),
              padding: const EdgeInsets.only(left: 26, right: 16),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 14, color: iconColor),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: active
                        ? _HighlighterLabel(label: label)
                        : Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                  if (locked)
                    Icon(Icons.lock_rounded,
                        size: 12, color: scheme.onSurfaceVariant)
                  else if (liveDot)
                    const _PulsingLiveDot()
                  else if (count > 0)
                    _CountBadge(count: count),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _badgeCount(BuildContext context) => switch (badge) {
        _Badge.chat => context
            .select<DashboardBadgeController, int>((c) => c.chatUnread),
        _Badge.notifications =>
          context.select<NotificationController, int>((c) => c.unread),
        null => 0,
      };
}

/// "Help & Support" — the one nav row that opens a sheet rather than a view.
///
/// Never padlocked, and never a [DashboardView]: support is the way out of a
/// locked account, so gating it behind the same paywall it exists to explain
/// would be exactly backwards. Mirrors the sidebar link the website added
/// alongside its floating widget.
/// "My Wrapped" — a route rather than a [DashboardView].
///
/// Kept off the view enum on purpose: that enum is one-for-one with the web's
/// `VIEW_TITLES`, and the recap is a full-screen story that would fight the
/// dashboard's topbar and drawer for the screen anyway.
class _WrappedLink extends StatelessWidget {
  const _WrappedLink();

  /// Whether the month that just ended has a recap the student has not opened.
  static bool _isUnseen(PrefsService prefs) {
    final now = DateTime.now();
    return prefs.wrappedSeen != monthKeyFor(DateTime(now.year, now.month - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unseen = _isUnseen(context.read<PrefsService>());

    return InkWell(
      onTap: () {
        final navigator = Navigator.of(context);
        navigator.pop();
        navigator.push(WrappedScreen.route());
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: Tokens.minTouchTarget),
        padding: const EdgeInsets.only(left: 26, right: 16),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: isDark
                    ? scheme.surfaceContainerHigh
                    : BlueprintPalette.b50,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: isDark ? scheme.onSurfaceVariant : BlueprintPalette.text3,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'My Wrapped',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (unseen)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: BlueprintPalette.b500,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: BlueprintPalette.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SupportLink extends StatelessWidget {
  const _SupportLink();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unread =
        context.select<DashboardBadgeController, int>((c) => c.supportUnread);

    return InkWell(
      onTap: () {
        // The drawer closes first — the sheet would otherwise open behind it —
        // and the sheet is raised from the navigator's own context, which
        // outlives the drawer element being torn down.
        final navigator = Navigator.of(context);
        navigator.pop();
        showSupportSheet(navigator.context);
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: Tokens.minTouchTarget),
        padding: const EdgeInsets.only(left: 26, right: 16),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: isDark
                    ? scheme.surfaceContainerHigh
                    : BlueprintPalette.b50,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.headset_mic_rounded,
                size: 14,
                color: isDark ? scheme.onSurfaceVariant : BlueprintPalette.text3,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Help & Support',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (unread > 0) _CountBadge(count: unread),
          ],
        ),
      ),
    );
  }
}

/// The active link's label, swept with a highlighter.
///
/// On the web this is a skewed `linear-gradient` behind the text; here it is a
/// rounded translucent slab, which is the closest a single box decoration gets.
class _HighlighterLabel extends StatelessWidget {
  const _HighlighterLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: BlueprintPalette.b500.withValues(alpha: isDark ? 0.24 : 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark ? BlueprintPalette.b100 : BlueprintPalette.b800,
          ),
        ),
      ),
    );
  }
}

/// `.sb-live-dot` — a 6px red dot on a 1.4s pulse.
class _PulsingLiveDot extends StatefulWidget {
  const _PulsingLiveDot();

  @override
  State<_PulsingLiveDot> createState() => _PulsingLiveDotState();
}

class _PulsingLiveDotState extends State<_PulsingLiveDot>
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
    // Respect the OS "reduce motion" setting — a pulsing dot is decoration, and
    // a static one carries the same meaning.
    if (MediaQuery.disableAnimationsOf(context)) return const _LiveDot();

    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.4).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: 0.7).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: const _LiveDot(),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'A class is live now',
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error,
            shape: BoxShape.circle,
          ),
        ),
      );
}

/// `.sb-badge` — unread count, capped at `99+`.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(100),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: scheme.onError,
          height: 1.1,
        ),
      ),
    );
  }
}

// ─── Upgrade card ────────────────────────────────────────────────────────────

/// `.ds-upgrade` — shown only to online free-plan students.
///
/// Physical-centre students are deliberately excluded: they pay a lesson fee at
/// the centre, and offering them an online plan would sell them the same access
/// twice.
class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({required this.profile});

  final AppUser? profile;

  @override
  Widget build(BuildContext context) {
    final plan = profile?.plan ?? 'free';
    final isPhysical = profile?.studentMode == 'physical';
    if (plan != 'free' || isPhysical) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 22, right: 14, top: 10, bottom: 4),
      child: Material(
        borderRadius: BorderRadius.circular(Tokens.rMd),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                BlueprintPalette.b600,
                BlueprintPalette.b500,
                BlueprintPalette.b400,
              ],
              stops: [0, 0.55, 1],
            ),
          ),
          child: InkWell(
            onTap: () {
              context.read<DashboardController>().select(DashboardView.settings);
              Navigator.of(context).maybePop();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.rocket_launch_rounded,
                          size: 13, color: BlueprintPalette.white),
                      const SizedBox(width: 6),
                      Text(
                        'Upgrade to Pro',
                        style: GoogleFonts.fraunces(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: BlueprintPalette.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Unlock all lessons + live classes',
                    style: TextStyle(
                      fontSize: 11,
                      color: BlueprintPalette.white.withValues(alpha: 0.75),
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

// ─── Sign out ────────────────────────────────────────────────────────────────

class _SignOutRow extends StatelessWidget {
  const _SignOutRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        const _DashedDivider(),
        Padding(
          padding: const EdgeInsets.only(left: 22, right: 16, top: 12, bottom: 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.errorContainer, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Tokens.rSm),
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: 15),
              label: const Text(
                'Sign Out',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Signing out wipes this student's on-device data, so it asks first — on a
  /// shared phone an accidental tap costs them their downloaded questions.
  Future<void> _confirmSignOut(BuildContext context) async {
    final session = context.read<SessionController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your downloaded questions and history on this device will be '
          'cleared. You can sign back in any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) await session.signOut();
  }
}
