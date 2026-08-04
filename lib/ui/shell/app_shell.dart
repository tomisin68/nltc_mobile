import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/attempt_repository.dart';
import '../core/state/activity_controller.dart';
import '../core/state/dashboard_controller.dart';
import '../core/state/practice_controller.dart';
import '../core/state/presence_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../announcements/announcements_screen.dart';
import '../cbt/bece_practice_screen.dart';
import '../cbt/cbt_practice_screen.dart';
import '../chat/chat_screen.dart';
import '../home/home_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../lessons/lessons_screen.dart';
import '../live/live_classes_screen.dart';
import '../mockexams/mock_exams_screen.dart';
import '../notes/study_notes_screen.dart';
import '../quicktests/quick_tests_screen.dart';
import '../quiz/official_quiz_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../support/support_fab.dart';
import 'access_banners.dart';
import 'dashboard_sidebar.dart';
import 'dashboard_topbar.dart';
import 'locked_view.dart';

/// The signed-in frame.
///
/// Mirrors the web's `DashboardPage`: a drawer of destinations, a topbar naming
/// the current one, a strip of access warnings, and the view itself. There is no
/// router — the dashboard swaps views in place, exactly as the website does, so
/// the drawer and topbar never rebuild between destinations.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  /// `FREE_VIEWS` on the web — reachable even when the account is locked.
  static const _freeViews = {
    DashboardView.home,
    DashboardView.profile,
    DashboardView.settings,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The shell is rebuilt from scratch on every sign-in, so this is also
      // where a second student on a shared phone gets a clean slate.
      context.read<DashboardController>().reset();
      context.read<PracticeController>().load();
      // Attempt history was wiped on the previous sign-out; reload it, then
      // push anything finished offline the last time the app was open.
      context.read<ActivityController>().reload();
      context.read<AttemptRepository>().syncPending();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A backgrounded app gets no timer callbacks, so a trial that ran out
  /// overnight is only noticed here. Without this the student comes back to a
  /// dashboard that still says "1 day left" until something else rebuilds it.
  ///
  /// It is also where presence is decided: the shell is the only thing that
  /// outlives every chat screen, so an app that went into the background
  /// mid-conversation still tells the other side the student has gone.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    context.read<PresenceController>().setForeground(foreground);
    if (foreground) {
      context.read<SessionController>().recheckAccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = context.select<DashboardController, DashboardView>(
      (c) => c.view,
    );
    final session = context.watch<SessionController>();
    final access = session.access;
    final viewIsFree = _freeViews.contains(view);
    final locked = access.isLocked && !viewIsFree;

    return Scaffold(
      drawer: const DashboardSidebar(),
      appBar: DashboardTopbar(title: view.title),
      // Deliberately outside the `locked` branch below: a student who cannot
      // get in is the one with the most urgent reason to reach somebody.
      //
      // Messages is the one exception. It builds its own Scaffold with a "new
      // conversation" button in the same corner, so support yields it there and
      // stays reachable from the sidebar instead — which costs nothing, because
      // Messages is not a free view and a locked account cannot open it anyway.
      floatingActionButton:
          view == DashboardView.chat ? null : const SupportFab(),
      body: SafeArea(
        top: false,
        child: locked
            ? LockedView(access: access)
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: Tokens.s4,
                      right: Tokens.s4,
                      top: Tokens.s3,
                    ),
                    child: AccessBanners(
                      access: access,
                      view: view,
                      viewIsFree: viewIsFree,
                    ),
                  ),
                  Expanded(child: _view(view)),
                ],
              ),
      ),
    );
  }

  /// The screen for [view].
  ///
  /// Keyed so switching destinations tears the previous one down — the web
  /// unmounts each view on nav, and a half-finished quiz must not be waiting
  /// when the student comes back to it.
  Widget _view(DashboardView view) {
    final key = ValueKey(
      '${view.name}:${context.read<DashboardController>().visitCount(view)}',
    );

    return switch (view) {
      DashboardView.home => HomeScreen(key: key),
      DashboardView.profile => ProfileScreen(key: key),
      // JSS students get the junior track here, the way the web routes `cbt` to
      // BECEPracticeView for them.
      DashboardView.cbt => DashboardSidebar.isJuniorStudent(
            context.read<SessionController>().profile,
          )
          ? BecePracticeScreen(key: key)
          : CbtPracticeScreen(key: key),
      DashboardView.bece => BecePracticeScreen(key: key),
      DashboardView.officialQuiz => OfficialQuizScreen(key: key),
      DashboardView.lessons => LessonsScreen(key: key),
      DashboardView.leaderboard => LeaderboardScreen(key: key),
      DashboardView.announcements => AnnouncementsScreen(key: key),
      DashboardView.notes => StudyNotesScreen(key: key),
      DashboardView.quickTest => QuickTestsScreen(key: key),
      DashboardView.mockExams => MockExamsScreen(key: key),
      DashboardView.live => LiveClassesScreen(key: key),
      DashboardView.chat => ChatScreen(key: key),
      DashboardView.settings => SettingsScreen(key: key),
    };
  }
}
