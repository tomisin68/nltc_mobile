import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/exam_result_repository.dart';
import '../../data/repositories/gamification_repository.dart';
import '../../data/repositories/live_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../data/services/mission_signals.dart';
import '../../domain/models/exam_result.dart';
import '../../domain/models/live_session.dart';
import '../core/state/activity_controller.dart';
import '../core/state/dashboard_controller.dart';
import '../core/state/session_controller.dart';
import '../core/state/xp_service.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/access_card.dart';
import '../live/livestream_screen.dart';
import 'widgets/action_rail.dart';
import 'widgets/hero_desk.dart';
import 'widgets/jump_back_in.dart';
import 'widgets/progress_notebook.dart';
import 'widgets/setup_checklist.dart';
import 'widgets/side_cards.dart';
import 'widgets/today_plan.dart';

/// The student's study desk.
///
/// Port of `src/pages/dashboard/HomeView.jsx`, in the order the web lays it out:
/// the ruled-paper hero, whatever is urgent (a live class, an unpaid fee, an
/// unfinished setup), the action rail, and then the numbered cards. The website
/// puts cards 04–06 in a right-hand column; on a phone there is one column, so
/// they follow on in their numbered order.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _rank;
  bool _loadingRank = true;

  /// Null while loading — the cards below tell that apart from "none".
  List<ExamResult>? _results;

  LiveSession? _liveSession;
  List<ScheduledClass> _upcoming = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null) return;

    final isJunior = session.profile?.isJunior ?? false;
    final gamification = context.read<GamificationRepository>();
    final resultRepository = context.read<ExamResultRepository>();
    final live = context.read<LiveRepository>();
    final schedule = context.read<ScheduleRepository>();

    // Fired together rather than in sequence: these are four independent reads and
    // the dashboard should not wait for the slowest to show the first.
    unawaited(
      gamification
          .myRank()
          .then((rank) {
            if (mounted) {
              setState(() {
                _rank = rank.rank;
                _loadingRank = false;
              });
            }
          })
          .catchError((_) {
            if (mounted) setState(() => _loadingRank = false);
          }),
    );

    unawaited(
      resultRepository
          .recent(uid)
          .then((results) {
            if (mounted) setState(() => _results = results);
          })
          .catchError((_) {
            if (mounted) setState(() => _results = const <ExamResult>[]);
          }),
    );

    unawaited(
      live.currentlyLive(isJunior: isJunior).then((found) {
        if (mounted) setState(() => _liveSession = found);
      }),
    );

    unawaited(
      schedule.upcoming().then((classes) {
        if (mounted) setState(() => _upcoming = classes);
      }),
    );
  }

  Future<void> _refresh() async {
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    await session.refreshProfile();
    if (!mounted) return;

    if (uid != null) context.read<ExamResultRepository>().invalidate(uid);
    await context.read<ActivityController>().syncNow();
    if (!mounted) return;

    setState(() {
      _results = null;
      _loadingRank = true;
    });
    await _load();
  }

  /// Joins the class in the banner.
  ///
  /// Access is re-read at the tap rather than trusted from the last build: the
  /// banner can sit on screen across the moment a trial runs out.
  Future<void> _joinLive(LiveSession live) async {
    final session = context.read<SessionController>();
    if (!session.access.active) {
      showToast('Upgrade to Pro to join live classes');
      context.read<DashboardController>().select(DashboardView.settings);
      return;
    }

    final uid = session.account?.uid;
    unawaited(
      context.read<XpService>().award(
        'join_live',
        meta: {'sessionId': live.id},
      ),
    );
    await context.read<MissionSignals>().set('join_live', uid);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LivestreamScreen(sessionId: live.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final profile = session.profile;
    final access = session.access;
    final isJunior = profile?.isJunior ?? false;

    // The fee alert is only for students who genuinely have to pay to get in. A
    // student inside their trial already has full access, so telling them their
    // account is "pending activation" would be wrong.
    final physicalUnpaid =
        profile != null &&
        profile.studentMode == 'physical' &&
        !profile.lessonFeePaid &&
        !access.active;

    final live = _liveSession;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
        children: [
          HeroDesk(
            profile: profile,
            rank: _rank,
            loadingRank: _loadingRank,
            sessionsThisWeek: sessionsSinceMonday(_results),
          ),
          const SizedBox(height: Tokens.s3),

          if (live != null) ...[
            LiveNowBanner(session: live, onJoin: () => _joinLive(live)),
            const SizedBox(height: Tokens.s3),
          ],

          if (physicalUnpaid) ...[
            const PaymentAlert(),
            const SizedBox(height: Tokens.s3),
          ],

          // The "please verify" banner is gone: a student cannot reach this
          // screen unverified any more — AuthGate holds them on the code screen
          // instead of the app — so the nag has nobody left to nag.

          // The app's own card: what is downloaded, and whether the account is
          // verified enough to sit an offline exam. The website has no equivalent
          // because it has no offline mode.
          AccessCard(access: access),
          const SizedBox(height: Tokens.s3),

          if (profile != null) ...[
            SetupChecklist(profile: profile, access: access),
            const SizedBox(height: Tokens.s3),
          ],

          ActionRail(isJunior: isJunior),
          const SizedBox(height: Tokens.s3),

          JumpBackIn(results: _results, isJunior: isJunior),
          const SizedBox(height: Tokens.s3),

          if (profile != null) ...[
            TodayPlan(profile: profile),
            const SizedBox(height: Tokens.s3),
          ],

          if (session.account != null) ...[
            ProgressNotebook(
              uid: session.account!.uid,
              results: _results,
              isJunior: isJunior,
            ),
            const SizedBox(height: Tokens.s3),
          ],

          if (profile != null) ...[
            WeeklyGoalCard(profile: profile, results: _results),
            const SizedBox(height: Tokens.s3),
          ],

          if (session.account != null) ...[
            WeeklyRaceCard(uid: session.account!.uid),
            const SizedBox(height: Tokens.s3),
          ],

          if (profile != null) ...[
            AchievementsCard(profile: profile),
            const SizedBox(height: Tokens.s3),
          ],

          UpcomingClassesCard(classes: _upcoming),
        ],
      ),
    );
  }
}
