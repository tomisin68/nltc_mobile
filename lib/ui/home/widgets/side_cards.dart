import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/gamification_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/exam_result.dart';
import '../../../domain/models/gamification.dart';
import '../../core/state/dashboard_controller.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/app_palette.dart';
import 'desk_card.dart';

/// Monday 00:00 local — the start of the study week the goal counts against.
DateTime mondayThisWeek([DateTime? now]) {
  final today = now ?? DateTime.now();
  final back = today.weekday == 7 ? 6 : today.weekday - 1;
  return DateTime(today.year, today.month, today.day)
      .subtract(Duration(days: back));
}

/// Practice sessions this student has done since Monday.
int sessionsSinceMonday(List<ExamResult>? results) {
  if (results == null) return 0;
  final since = mondayThisWeek();
  return results
      .where((r) => r.submittedAt != null && r.submittedAt!.isAfter(since))
      .length;
}

// ─── Weekly goal ────────────────────────────────────────────────────────────

/// The sessions-per-week dial.
///
/// Port of `WeeklyGoalCard`. The goal is the student's own — they set it with the
/// stepper, and it saves optimistically because a dial that lags a tap feels
/// broken.
class WeeklyGoalCard extends StatefulWidget {
  const WeeklyGoalCard({
    super.key,
    required this.profile,
    required this.results,
  });

  final AppUser profile;
  final List<ExamResult>? results;

  @override
  State<WeeklyGoalCard> createState() => _WeeklyGoalCardState();
}

class _WeeklyGoalCardState extends State<WeeklyGoalCard> {
  /// Set while a write is in flight, so the number moves at once.
  int? _pendingGoal;
  bool _saving = false;

  int get _goal => _pendingGoal ?? widget.profile.weeklyGoal.clamp(1, 21);

  Future<void> _setGoal(int next) async {
    final clamped = next.clamp(1, 21);
    if (clamped == _goal || _saving) return;

    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return;

    setState(() {
      _pendingGoal = clamped;
      _saving = true;
    });
    try {
      await context.read<ProfileRepository>().setWeeklyGoal(uid, clamped);
    } catch (_) {
      // The profile stream is the source of truth; dropping the local override
      // lets it correct the number on its own.
      if (mounted) setState(() => _pendingGoal = null);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sessions = sessionsSinceMonday(widget.results);
    final goal = _goal;
    final met = sessions >= goal;
    final percent = (sessions / goal).clamp(0.0, 1.0);
    final weeklyXp = widget.profile.weeklyXpThisWeek;
    final numbers = NumberFormat.decimalPattern();

    return DeskCard(
      number: '04',
      title: 'Weekly Goal',
      trailing: met
          ? DeskPill(label: 'Goal met 🎉', tone: BlueprintPalette.success)
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(end: percent),
                  duration: const Duration(milliseconds: 800),
                  curve: Motion.emphasized,
                  builder: (context, value, _) => SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 9,
                      strokeCap: StrokeCap.round,
                      backgroundColor: scheme.surfaceContainerHigh,
                      valueColor: AlwaysStoppedAnimation(
                        met ? BlueprintPalette.success : scheme.primary,
                      ),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '$sessions'),
                          TextSpan(
                            text: '/$goal',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      style: GoogleFonts.fraunces(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'SESSIONS',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Tokens.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _note(sessions, goal, met, weeklyXp, numbers),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Tokens.s2),
                Row(
                  children: [
                    _StepButton(
                      icon: Icons.remove_rounded,
                      onTap: goal <= 1 || _saving ? null : () => _setGoal(goal - 1),
                      semanticLabel: 'Lower weekly goal',
                    ),
                    const SizedBox(width: 9),
                    Text(
                      '$goal / week',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 9),
                    _StepButton(
                      icon: Icons.add_rounded,
                      onTap:
                          goal >= 21 || _saving ? null : () => _setGoal(goal + 1),
                      semanticLabel: 'Raise weekly goal',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _note(
    int sessions,
    int goal,
    bool met,
    int weeklyXp,
    NumberFormat numbers,
  ) {
    final earned =
        weeklyXp > 0 ? " You've earned ${numbers.format(weeklyXp)} XP so far." : '';
    if (met) {
      return 'Goal smashed — $sessions sessions this week. Raise the bar?$earned';
    }
    if (sessions == 0) {
      return 'Aim for $goal practice session${goal == 1 ? '' : 's'} this week. '
          'Start with just one today.$earned';
    }
    return '${goal - sessions} more to hit this week\'s goal — '
        "you've got this.$earned";
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: scheme.outlineVariant, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 13,
            color: onTap == null ? scheme.onSurfaceVariant : scheme.primary,
          ),
        ),
      ),
    );
  }
}

// ─── This week's race ───────────────────────────────────────────────────────

/// The weekly XP board, with the reset counting down.
class WeeklyRaceCard extends StatefulWidget {
  const WeeklyRaceCard({super.key, required this.uid});

  final String uid;

  @override
  State<WeeklyRaceCard> createState() => _WeeklyRaceCardState();
}

class _WeeklyRaceCardState extends State<WeeklyRaceCard> {
  WeeklyRace? _race;
  Timer? _ticker;
  String _countdown = '';

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  void initState() {
    super.initState();
    _load();
    _tick();
    // Once a minute is enough for a countdown shown in hours and minutes.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final race = await context.read<GamificationRepository>().weeklyRace();
    if (mounted) setState(() => _race = race);
  }

  void _tick() {
    final remaining = WeeklyRace.nextReset().difference(DateTime.now());
    if (!mounted) return;
    setState(() => _countdown = _format(remaining));
  }

  static String _format(Duration remaining) {
    if (remaining.isNegative) return 'Resetting…';
    final hours = remaining.inHours;
    if (hours >= 24) return '${hours ~/ 24}d ${hours % 24}h';
    return '${hours}h ${remaining.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final race = _race;
    final numbers = NumberFormat.decimalPattern();

    return DeskCard(
      number: '05',
      title: "This Week's Race",
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hourglass_bottom_rounded,
            size: 11,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            _countdown,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: Tokens.s2),
      footer: DeskLink(
        label: 'Full leaderboard',
        onTap: () => context
            .read<DashboardController>()
            .select(DashboardView.leaderboard),
      ),
      child: race == null
          ? const DeskCardSpinner()
          : race.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s4,
                    vertical: Tokens.s3,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 15, color: scheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Quiet week so far — be the first on the board!',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (final entry in race.entries)
                      _RaceRow(
                        rank: entry.rank,
                        medal: entry.rank <= 3 ? _medals[entry.rank - 1] : null,
                        name: entry.displayName,
                        initial: entry.initial,
                        xp: numbers.format(entry.weeklyXp),
                        isMe: entry.uid == widget.uid,
                      ),
                    if (race.myRank != null && race.myRank! > race.entries.length)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Tokens.s4,
                          Tokens.s2,
                          Tokens.s4,
                          0,
                        ),
                        child: Text(
                          'Your rank this week: #${race.myRank} — keep pushing!',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _RaceRow extends StatelessWidget {
  const _RaceRow({
    required this.rank,
    required this.medal,
    required this.name,
    required this.initial,
    required this.xp,
    required this.isMe,
  });

  final int rank;
  final String? medal;
  final String name;
  final String initial;
  final String xp;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMe ? 6 : 0),
      padding: EdgeInsets.symmetric(
        horizontal: isMe ? 10 : Tokens.s4,
        vertical: 7,
      ),
      decoration: isMe
          ? BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(Tokens.rXs),
            )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              medal ?? '#$rank',
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [BlueprintPalette.b600, BlueprintPalette.b400],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              isMe ? '$name (You)' : name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$xp XP',
            style: GoogleFonts.fraunces(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Achievements ───────────────────────────────────────────────────────────

/// Earned medals, and the three the student is closest to.
class AchievementsCard extends StatelessWidget {
  const AchievementsCard({super.key, required this.profile});

  final AppUser profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = Achievement.evaluate(profile);
    final earned = all.where((a) => a.earned).toList();
    final nextUp = (all.where((a) => !a.earned).toList()
          ..sort((a, b) => b.progress.compareTo(a.progress)))
        .take(3)
        .toList();

    return DeskCard(
      number: '06',
      title: 'Achievements',
      trailing: DeskPill(label: '${earned.length} / ${all.length}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (earned.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final badge in earned)
                  Tooltip(
                    message: '${badge.label} — ${badge.description}',
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.surfaceContainerHigh,
                        border: Border.all(
                          color: scheme.outlineVariant,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badge.icon,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.s4),
          ],
          if (nextUp.isEmpty)
            Center(
              child: Text(
                "All badges earned — you're a legend! 🏆",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
            )
          else ...[
            Text(
              'NEXT UP',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Tokens.s2),
            for (final badge in nextUp)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        badge.icon,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            badge.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: badge.progress,
                              minHeight: 4,
                              backgroundColor: scheme.surfaceContainerHigh,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Tokens.s2),
                    Text(
                      '${(badge.progress * 100).round()}%',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Upcoming classes ───────────────────────────────────────────────────────

/// The next few classes on the timetable, with a tear-off calendar date.
class UpcomingClassesCard extends StatelessWidget {
  const UpcomingClassesCard({super.key, required this.classes});

  final List<ScheduledClass> classes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (classes.isEmpty) return const SizedBox.shrink();

    return DeskCard(
      number: '07',
      title: 'Upcoming Classes',
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final entry in classes)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.s4,
                vertical: Tokens.s3,
              ),
              decoration: BoxDecoration(
                border: entry == classes.last
                    ? null
                    : Border(bottom: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  _CalendarChip(date: entry.scheduledAt),
                  const SizedBox(width: Tokens.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          [
                            if (entry.subject != null) entry.subject!,
                            if (entry.scheduledAt != null)
                              DateFormat('EEE · h:mm a')
                                  .format(entry.scheduledAt!),
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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

class _CalendarChip extends StatelessWidget {
  const _CalendarChip({required this.date});

  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 40,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: BlueprintPalette.b200, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: BlueprintPalette.b600,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              date == null ? '—' : DateFormat('MMM').format(date!).toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Colors.white,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 3),
            child: Text(
              date == null ? '?' : '${date!.day}',
              style: GoogleFonts.fraunces(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                height: 1,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
