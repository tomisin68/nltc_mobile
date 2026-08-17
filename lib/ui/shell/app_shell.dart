import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/attempt_repository.dart';
import '../../data/services/push_service.dart';
import '../../domain/models/app_notification.dart';
import '../../domain/pro_features.dart';
import '../core/state/activity_controller.dart';
import '../core/state/dashboard_controller.dart';
import '../core/state/practice_controller.dart';
import '../core/state/presence_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/in_app_browser.dart';
import '../core/widgets/pro_gate.dart';
import '../announcements/announcements_screen.dart';
import '../blog/blog_screen.dart';
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
import '../timetable/timetable_screen.dart';
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
  StreamSubscription<AppNotification>? _tapSub;

  /// The last push acted on. A tap that launched the app from cold arrives both
  /// on the stream and as [PushService.pendingTap], and neither can be dropped
  /// without losing the other case — so the id decides.
  String? _handledTap;

  /// `FREE_VIEWS` on the web — reachable even when the account is locked.
  ///
  /// The blog is on the list because it is published openly on the website:
  /// locking a student out of something they could read in any browser would
  /// only teach them to leave the app to read it.
  static const _freeViews = {
    DashboardView.home,
    DashboardView.profile,
    DashboardView.settings,
    DashboardView.blog,
  };

  /// The views a free account does not include at all — Pro only.
  ///
  /// The other half of the same idea as [_freeViews], one step up: those stay
  /// open when a paid account lapses, while these are never open without a
  /// payment, not even during the three free days. My Wrapped is the third
  /// Pro-only feature and is gated at its sidebar link, having no view of its
  /// own. See [ProFeature].
  static const _proViews = {
    DashboardView.chat: ProFeature.messages,
    DashboardView.live: ProFeature.liveClasses,
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

      // A student who taps "New on NLTC Blog" in their tray expects the
      // article, not the dashboard. Wired here because the shell is the first
      // thing with a Navigator that outlives every view.
      final push = context.read<PushService>();
      _tapSub = push.taps.listen(_openFromPush);
      final pending = push.pendingTap;
      if (pending != null) _openFromPush(pending);
    });
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Follows a tapped push, when it points somewhere the app can go.
  ///
  /// Only blog links are followed. The other routes the backend attaches are
  /// website URLs (`/student.html?view=chat`) that would land the student on a
  /// login page they have no business seeing, so those still just open the app.
  void _openFromPush(AppNotification notification) {
    if (!mounted || notification.id == _handledTap) return;
    _handledTap = notification.id;
    context.read<PushService>().clearPendingTap(notification.id);

    final article = blogUrlForRoute(notification.route);
    if (article == null) return;
    openInAppBrowser(context, article, title: 'NLTC Blog');
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

    // A Pro-only destination a free account has walked into — from the sidebar,
    // a dashboard card, or a tapped chat push. The upsell stands in for the view
    // rather than the tap being swallowed, so the student learns what is behind
    // it instead of finding a link that does nothing. The account lock outranks
    // it: somebody whose payment has lapsed needs telling that, not an offer.
    final proFeature = _proViews[view];
    final needsPro = proFeature != null && !locked && !access.isPro;

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
      // A free account being shown the upsell in its place has no such button,
      // so the corner is free again and support comes back.
      floatingActionButton: view == DashboardView.chat && !needsPro
          ? null
          : const SupportFab(),
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
                  Expanded(
                    child: needsPro
                        // The screen is never built, so its Firestore listeners
                        // never start: a free account does not quietly stream a
                        // chat list or a live schedule it cannot open.
                        ? ProUpsellView(feature: proFeature, access: access)
                        : _view(view),
                  ),
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
      DashboardView.cbt =>
        DashboardSidebar.isJuniorStudent(
              context.read<SessionController>().profile,
            )
            ? BecePracticeScreen(key: key)
            : CbtPracticeScreen(key: key),
      DashboardView.bece => BecePracticeScreen(key: key),
      DashboardView.officialQuiz => OfficialQuizScreen(key: key),
      DashboardView.lessons => LessonsScreen(key: key),
      DashboardView.leaderboard => LeaderboardScreen(key: key),
      DashboardView.announcements => AnnouncementsScreen(key: key),
      DashboardView.blog => BlogScreen(key: key),
      DashboardView.notes => StudyNotesScreen(key: key),
      DashboardView.quickTest => QuickTestsScreen(key: key),
      DashboardView.mockExams => MockExamsScreen(key: key),
      DashboardView.live => LiveClassesScreen(key: key),
      DashboardView.timetable => TimetableScreen(key: key),
      DashboardView.chat => ChatScreen(key: key),
      DashboardView.settings => SettingsScreen(key: key),
    };
  }
}
