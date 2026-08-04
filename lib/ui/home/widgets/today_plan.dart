import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/mission_signals.dart';
import '../../../domain/models/app_user.dart';
import '../../core/state/dashboard_controller.dart';
import '../../core/state/session_controller.dart';
import '../../core/state/xp_service.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/ruled_paper.dart';
import 'desk_card.dart';

/// One thing to do today.
class Mission {
  const Mission({
    required this.id,
    required this.label,
    required this.icon,
    required this.view,
    this.xp = 25,
  });

  final String id;
  final String label;
  final IconData icon;
  final DashboardView view;
  final int xp;
}

/// The pool the day's three tasks are drawn from.
///
/// Ids match the web's `MISSION_POOL` exactly, because the completion signals are
/// written under those ids and a student may finish a task on the website and tick
/// it off in the app.
const _seniorPool = <Mission>[
  Mission(
    id: 'watch_video',
    label: 'Watch one video lesson',
    icon: Icons.play_circle_rounded,
    view: DashboardView.lessons,
  ),
  Mission(
    id: 'cbt_session',
    label: 'Complete a CBT practice test',
    icon: Icons.laptop_mac_rounded,
    view: DashboardView.cbt,
  ),
  Mission(
    id: 'topic_session',
    label: 'Practise by topic',
    icon: Icons.place_rounded,
    view: DashboardView.cbt,
  ),
  Mission(
    id: 'join_live',
    label: 'Join a live class',
    icon: Icons.sensors_rounded,
    view: DashboardView.live,
  ),
  Mission(
    id: 'mock_exam',
    label: 'Attempt a mock exam',
    icon: Icons.school_rounded,
    view: DashboardView.mockExams,
  ),
  Mission(
    id: 'leaderboard',
    label: 'Check the leaderboard',
    icon: Icons.emoji_events_rounded,
    view: DashboardView.leaderboard,
  ),
  Mission(
    id: 'study_mode',
    label: 'Do a study mode session',
    icon: Icons.menu_book_rounded,
    view: DashboardView.cbt,
  ),
  Mission(
    id: 'waec_practice',
    label: 'Take a WAEC practice test',
    icon: Icons.assignment_rounded,
    view: DashboardView.cbt,
  ),
  Mission(
    id: 'postutme',
    label: 'Try a Post UTME session',
    icon: Icons.account_balance_rounded,
    view: DashboardView.cbt,
  ),
  Mission(
    id: 'study_notes',
    label: 'Study a topic from Study Notes',
    icon: Icons.book_rounded,
    view: DashboardView.notes,
  ),
];

/// The junior pool has no video missions — there are no JSS videos to watch.
const _juniorPool = <Mission>[
  Mission(
    id: 'cbt_session',
    label: 'Complete a BECE practice session',
    icon: Icons.laptop_mac_rounded,
    view: DashboardView.bece,
  ),
  Mission(
    id: 'topic_session',
    label: 'Practise by topic',
    icon: Icons.place_rounded,
    view: DashboardView.bece,
  ),
  Mission(
    id: 'join_live',
    label: 'Join a live class',
    icon: Icons.sensors_rounded,
    view: DashboardView.live,
  ),
  Mission(
    id: 'leaderboard',
    label: 'Check the leaderboard',
    icon: Icons.emoji_events_rounded,
    view: DashboardView.leaderboard,
  ),
  Mission(
    id: 'study_mode',
    label: 'Do a study mode session',
    icon: Icons.menu_book_rounded,
    view: DashboardView.bece,
  ),
  Mission(
    id: 'study_notes',
    label: 'Study a topic from Study Notes',
    icon: Icons.book_rounded,
    view: DashboardView.notes,
  ),
];

/// Today's three tasks.
///
/// Port of `TodayPlan`. The set is seeded from the date, so every student gets the
/// same three on a given day and the app and website agree without a round trip.
/// A task can only be ticked once its signal has actually been recorded — you
/// cannot claim XP for a lesson you did not watch.
class TodayPlan extends StatefulWidget {
  const TodayPlan({super.key, required this.profile});

  final AppUser profile;

  /// The seeded draw. Exposed for the same reason the web exports it: it is pure,
  /// and a test can check that the same date gives the same three.
  static List<String> dailyTaskIds(String dateKey, List<Mission> pool) {
    // The web's `seededRandom` — a 32-bit integer hash, iterated. Reproduced
    // exactly (including the `Math.imul` semantics, which is what the masking
    // below stands in for) so both platforms draw the same set.
    var seed = int.tryParse(dateKey.replaceAll('-', '')) ?? 0;
    double next() {
      seed = _imul(seed ^ (seed >>> 16), 0x45d9f3b);
      seed = _imul(seed ^ (seed >>> 16), 0x45d9f3b);
      seed = seed ^ (seed >>> 16);
      return (seed & 0xFFFFFFFF) / 4294967296;
    }

    final weighted = [
      for (final mission in pool) (id: mission.id, roll: next()),
    ]..sort((a, b) => a.roll.compareTo(b.roll));

    return weighted.take(3).map((w) => w.id).toList();
  }

  /// JavaScript's `Math.imul`: a 32-bit signed multiply.
  static int _imul(int a, int b) {
    final product = (a & 0xFFFFFFFF) * (b & 0xFFFFFFFF);
    final low = product & 0xFFFFFFFF;
    return low >= 0x80000000 ? low - 0x100000000 : low;
  }

  @override
  State<TodayPlan> createState() => _TodayPlanState();
}

class _TodayPlanState extends State<TodayPlan> {
  /// Ticked locally the moment the button is pressed, so the bubble fills without
  /// waiting for Firestore to come back.
  final Set<String> _justCompleted = {};

  String? _marking;

  List<Mission> get _pool =>
      widget.profile.isJunior ? _juniorPool : _seniorPool;

  String get _today => ProfileRepository.todayKey();

  bool get _missionIsToday => widget.profile.dailyMission?.date == _today;

  List<Mission> get _tasks {
    final ids = _missionIsToday
        ? widget.profile.dailyMission!.taskIds
        : TodayPlan.dailyTaskIds(_today, _pool);
    return [
      for (final id in ids)
        ..._pool.where((m) => m.id == id).take(1),
    ];
  }

  Set<String> get _completed => {
        if (_missionIsToday) ...widget.profile.dailyMission!.completed,
        ..._justCompleted,
      };

  @override
  void initState() {
    super.initState();
    // A day has rolled over: write the new set so the website sees the same three.
    if (!_missionIsToday) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _rollOver());
    }
  }

  Future<void> _rollOver() async {
    final uid = context.read<SessionController>().account?.uid;
    if (uid == null || !mounted) return;
    try {
      await context.read<ProfileRepository>().startDailyMission(
            uid,
            _today,
            TodayPlan.dailyTaskIds(_today, _pool),
          );
    } catch (_) {
      // The set is derived from the date anyway, so a failed write costs nothing
      // today — the tasks still show, they just aren't recorded yet.
    }
  }

  Future<void> _markDone(Mission mission) async {
    final uid = context.read<SessionController>().account?.uid;
    if (uid == null || _marking != null || _completed.contains(mission.id)) {
      return;
    }

    setState(() {
      _marking = mission.id;
      _justCompleted.add(mission.id);
    });

    try {
      await context.read<ProfileRepository>().completeMission(uid, mission.id);
      // XP is claimed separately, and only once — the signal store is what stops
      // a student earning it twice by signing out and back in.
      if (mounted) {
        await context.read<XpService>().award('daily_mission');
      }
    } catch (_) {
      if (mounted) setState(() => _justCompleted.remove(mission.id));
    } finally {
      if (mounted) setState(() => _marking = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tasks = _tasks;
    final completed = _completed;
    final doneCount = tasks.where((t) => completed.contains(t.id)).length;
    final allDone = tasks.isNotEmpty && doneCount == tasks.length;

    return DeskCard(
      number: '02',
      title: "Today's Study Plan",
      trailing: DeskPill(label: '$doneCount / ${tasks.length} done'),
      padding: EdgeInsets.zero,
      footer: allDone
          ? null
          : Row(
              children: [
                Icon(
                  Icons.autorenew_rounded,
                  size: 11,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Resets daily · earn 25 XP per completed task',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
      child: allDone
          ? _PlanComplete()
          : RuledPaper(
              lineSpacing: 52,
              child: Column(
                children: [
                  for (final task in tasks)
                    _TaskRow(
                      mission: task,
                      done: completed.contains(task.id),
                      marking: _marking == task.id,
                      // The signal is the proof: it is written by the screen that
                      // actually completes the task, so a student cannot tick off
                      // a lesson they never opened.
                      signalReady: context.read<MissionSignals>().has(
                            task.id,
                            context.read<SessionController>().account?.uid,
                          ),
                      onGo: () =>
                          context.read<DashboardController>().select(task.view),
                      onMark: () => _markDone(task),
                      isLast: task == tasks.last,
                    ),
                ],
              ),
            ),
    );
  }
}

class _PlanComplete extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(Tokens.s4),
      child: Row(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 26)),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plan complete — brilliant work!',
                  style: GoogleFonts.fraunces(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Fresh tasks land tomorrow morning. Keep practising in the '
                  'meantime.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
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

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.mission,
    required this.done,
    required this.marking,
    required this.signalReady,
    required this.onGo,
    required this.onMark,
    required this.isLast,
  });

  final Mission mission;
  final bool done;
  final bool marking;
  final bool signalReady;
  final VoidCallback onGo;
  final VoidCallback onMark;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s4,
        vertical: Tokens.s2,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          // The OMR bubble — the same shape a student shades on a real answer
          // sheet, which is the whole joke of the design.
          AnimatedContainer(
            duration: Motion.fast,
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? scheme.primary : scheme.surfaceContainerLowest,
              border: Border.all(
                color: done ? scheme.primary : BlueprintPalette.b300,
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: done
                ? Icon(Icons.check_rounded, size: 13, color: scheme.onPrimary)
                : null,
          ),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mission.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: done ? scheme.onSurfaceVariant : scheme.onSurface,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  '+${mission.xp} XP',
                  style: GoogleFonts.caveat(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
          if (done)
            Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 13,
                  color: BlueprintPalette.success,
                ),
                const SizedBox(width: 4),
                Text(
                  'Done',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: BlueprintPalette.success,
                  ),
                ),
              ],
            )
          else ...[
            _SmallButton(label: 'Go', onTap: onGo, filled: false),
            const SizedBox(width: 6),
            _SmallButton(
              label: 'Done',
              icon: Icons.check_rounded,
              // Disabled until the task is genuinely finished; the tooltip says so
              // rather than leaving a dead button unexplained.
              onTap: signalReady && !marking ? onMark : null,
              filled: true,
              busy: marking,
              tooltip: signalReady
                  ? 'Mark as done'
                  : 'Complete the task first, then tick it off',
            ),
          ],
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onTap,
    required this.filled,
    this.icon,
    this.busy = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final IconData? icon;
  final bool busy;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = filled
        ? FilledButton.tonalIcon(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: busy
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, size: 13),
            label: Text(label),
          )
        : OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Text(label),
          );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
