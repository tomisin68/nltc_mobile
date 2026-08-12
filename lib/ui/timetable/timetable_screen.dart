import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/live_repository.dart';
import '../../data/services/mission_signals.dart';
import '../../domain/models/live_session.dart';
import '../core/state/dashboard_controller.dart';
import '../core/state/session_controller.dart';
import '../core/state/xp_service.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/skeleton.dart';
import '../live/livestream_screen.dart';

/// The week, laid out as a page of the student's timetable.
///
/// The live hall answers "what can I join?" and so is sorted newest-first, with
/// whatever is on air pulled to the top. This answers the different question of
/// "when is my week?" — every class on the day it falls, in the order the days
/// run, including the days with nothing on them. A free Thursday is information
/// a student plans around, so an empty day is drawn rather than skipped.
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  StreamSubscription<List<LiveSession>>? _subscription;
  List<LiveSession>? _sessions;

  /// Weeks away from the one containing today. 0 is this week.
  int _weekOffset = 0;

  /// Keeps "in 2h" and the today marker honest without a Firestore write.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final isJunior =
        context.read<SessionController>().profile?.isJunior ?? false;
    _subscription = context
        .read<LiveRepository>()
        .watchTimetable(isJunior: isJunior)
        .listen(
          (sessions) => setState(() => _sessions = sessions),
          onError: (_) => setState(() => _sessions = const []),
        );
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  /// The Monday of the week [offset] weeks from today.
  ///
  /// Built by day arithmetic on the calendar fields rather than by adding a
  /// `Duration`, so a week that straddles a month or year boundary still lands
  /// on the right date.
  static DateTime _weekStart(int offset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - DateTime.monday) + offset * 7,
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Jumps to whichever week holds [date].
  void _goToWeekOf(DateTime date) {
    final thisMonday = _weekStart(0);
    final thatMonday = DateTime(
      date.year,
      date.month,
      date.day - (date.weekday - DateTime.monday),
    );
    // Rounded, not truncated: `inDays` floors, and an hour of drift either side
    // of a week boundary would otherwise land the student a week off.
    final weeks = (thatMonday.difference(thisMonday).inHours / 168).round();
    setState(() => _weekOffset = weeks);
  }

  Future<void> _join(LiveSession session) async {
    final controller = context.read<SessionController>();
    // Re-read on the tap: the row can sit on screen across the access boundary,
    // and a sub-second stale render must not buy a session.
    if (!controller.access.active) {
      showToast('Upgrade to Pro to join live classes');
      context.read<DashboardController>().select(DashboardView.settings);
      return;
    }
    if (session.channel.isEmpty) {
      showToast(
        'This class has no room set up yet — ask your tutor.',
        variant: ToastVariant.error,
      );
      return;
    }

    unawaited(
      context
          .read<XpService>()
          .award('join_live', meta: {'sessionId': session.id}),
    );
    await context.read<MissionSignals>().set('join_live', controller.account?.uid);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LivestreamScreen(sessionId: session.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;

    const header = PageHeader(
      title: 'Timetable',
      subtitle: 'Your week at a glance — every class your tutors have put on a '
          'date, on the day it falls.',
    );

    if (sessions == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
        children: const [
          header,
          SkeletonListItem(lines: 2),
          SizedBox(height: Tokens.s3),
          SkeletonListItem(lines: 3),
          SizedBox(height: Tokens.s3),
          SkeletonListItem(lines: 2),
        ],
      );
    }

    final monday = _weekStart(_weekOffset);
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];
    final byDay = {
      for (final day in days)
        day: sessions.where((s) => _sameDay(s.slotAt!, day)).toList(),
    };
    final weekIsEmpty = byDay.values.every((list) => list.isEmpty);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
      children: [
        header,
        _WeekBar(
          monday: monday,
          offset: _weekOffset,
          onPrevious: () => setState(() => _weekOffset--),
          onNext: () => setState(() => _weekOffset++),
          onToday: _weekOffset == 0 ? null : () => setState(() => _weekOffset = 0),
        ),
        const SizedBox(height: Tokens.s4),
        if (weekIsEmpty)
          _EmptyWeek(
            sessions: sessions,
            monday: monday,
            onJump: _goToWeekOf,
          )
        else
          for (final day in days)
            _DayBlock(
              day: day,
              classes: byDay[day] ?? const [],
              isToday: _sameDay(day, DateTime.now()),
              onJoin: _join,
            ),
      ],
    );
  }
}

// ─── Week bar ────────────────────────────────────────────────────────────────

/// The pager: which week is on screen, and the arrows either side of it.
class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.monday,
    required this.offset,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime monday;
  final int offset;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Null on the current week — there is nowhere for "Today" to go.
  final VoidCallback? onToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);

    // Named while the name still means something. Past "next week" a student is
    // navigating by date, and a date is what helps them.
    final label = switch (offset) {
      0 => 'This week',
      1 => 'Next week',
      -1 => 'Last week',
      _ => monday.month == sunday.month
          ? '${DateFormat('d').format(monday)} – ${DateFormat('d MMM').format(sunday)}'
          : '${DateFormat('d MMM').format(monday)} – ${DateFormat('d MMM').format(sunday)}',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s2, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous week',
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.fraunces(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: scheme.onSurface,
                  ),
                ),
                // The dates stay on screen even when the label is a word, so
                // "next week" is never ambiguous about which dates it means.
                Text(
                  '${DateFormat('d MMM').format(monday)} – '
                  '${DateFormat('d MMM').format(sunday)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onToday != null)
            TextButton(
              onPressed: onToday,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s2),
              ),
              child: const Text('Today', style: TextStyle(fontSize: 12)),
            ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next week',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ─── A day ───────────────────────────────────────────────────────────────────

/// One day of the week, with whatever falls on it.
class _DayBlock extends StatelessWidget {
  const _DayBlock({
    required this.day,
    required this.classes,
    required this.isToday,
    required this.onJoin,
  });

  final DateTime day;
  final List<LiveSession> classes;
  final bool isToday;
  final void Function(LiveSession) onJoin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: isToday
                      ? BlueprintPalette.b600
                      : (isDark
                          ? scheme.surfaceContainerHigh
                          : BlueprintPalette.b50),
                  borderRadius: BorderRadius.circular(Tokens.rXs),
                ),
                child: Column(
                  children: [
                    Text(
                      DateFormat('EEE').format(day).toUpperCase(),
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                        color: isToday
                            ? BlueprintPalette.white.withValues(alpha: 0.85)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      DateFormat('d').format(day),
                      style: GoogleFonts.fraunces(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        color: isToday
                            ? BlueprintPalette.white
                            : scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Tokens.s3),
              if (isToday)
                Text(
                  'TODAY',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: scheme.primary,
                  ),
                ),
              if (isToday) const SizedBox(width: Tokens.s2),
              Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
            ],
          ),
          const SizedBox(height: Tokens.s2),
          if (classes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 54, bottom: 2),
              child: Text(
                'No classes',
                style: TextStyle(
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            )
          else
            for (final session in classes)
              Padding(
                padding: const EdgeInsets.only(left: 54, bottom: Tokens.s2),
                child: _ClassRow(
                  session: session,
                  onJoin: () => onJoin(session),
                ),
              ),
        ],
      ),
    );
  }
}

/// One class on a day: when it runs, what it is, and the way in if it is on now.
class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.session, required this.onJoin});

  final LiveSession session;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slot = session.slotAt!;
    final ended = session.hasEnded;

    return Opacity(
      // A finished class stays on the page — it is what the week held — but it
      // steps back so the eye lands on what is still to come.
      opacity: ended ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(Tokens.s3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(Tokens.rSm),
          border: Border.all(
            color: session.isLive
                ? scheme.error.withValues(alpha: 0.35)
                : scheme.outlineVariant,
            width: session.isLive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  DateFormat('h:mm a').format(slot),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: session.isLive ? scheme.error : scheme.primary,
                  ),
                ),
                const SizedBox(width: Tokens.s2),
                if (session.isLive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.error,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: Colors.white,
                      ),
                    ),
                  )
                else if (ended)
                  Text(
                    'Finished',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else if (slot.isAfter(DateTime.now()))
                  Text(
                    'in ${_countdown(slot.difference(DateTime.now()))}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              session.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.3,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (session.subject != null) session.subject!,
                if (session.hostName != null) session.hostName!,
              ].join(' · '),
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (session.isLive) ...[
              const SizedBox(height: Tokens.s2),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onJoin,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                  label: const Text('Join now'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _countdown(Duration until) {
    final minutes = until.inMinutes;
    final hours = minutes ~/ 60;
    if (hours > 0) return '${hours}h ${minutes % 60}m';
    return '${minutes < 1 ? 1 : minutes}m';
  }
}

// ─── Empty week ──────────────────────────────────────────────────────────────

/// Shown instead of seven blank days.
///
/// Seven "No classes" rows say the same thing seven times. Worse, a student
/// paging forward through a quiet stretch has no idea how far to keep tapping —
/// so when there is a class further out, this offers the week it is in.
class _EmptyWeek extends StatelessWidget {
  const _EmptyWeek({
    required this.sessions,
    required this.monday,
    required this.onJump,
  });

  final List<LiveSession> sessions;
  final DateTime monday;
  final void Function(DateTime) onJump;

  @override
  Widget build(BuildContext context) {
    final nextMonday = DateTime(monday.year, monday.month, monday.day + 7);
    // `sessions` is already sorted forwards, so the first match is the nearest.
    final next = sessions
        .where((s) => !s.slotAt!.isBefore(nextMonday))
        .firstOrNull
        ?.slotAt;

    return EmptyState(
      icon: Icons.event_available_rounded,
      title: 'Nothing on this week',
      // "after this week", not "next" — a student paging through a past week
      // would otherwise be told a class that has already run is still coming.
      message: next == null
          ? 'Classes appear here as soon as a tutor puts one on a date. Check '
              'back, or look through the weeks either side.'
          : 'This week is clear. The next class on the timetable after it is '
              'on ${DateFormat('EEEE d MMMM').format(next)}.',
      actionLabel: next == null ? null : 'Go to that week',
      onAction: next == null ? null : () => onJump(next),
    );
  }
}

