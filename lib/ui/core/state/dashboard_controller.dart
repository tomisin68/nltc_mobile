import 'package:flutter/foundation.dart';

/// The destinations in the student dashboard.
///
/// One-for-one with `VIEW_TITLES` in the web app's `src/pages/DashboardPage.jsx`
/// — the app and the website must offer the same places to go, under the same
/// names, or a student moving between them has to relearn the product.
enum DashboardView {
  home('Dashboard'),
  profile('My Profile'),
  lessons('Video Lessons'),
  cbt('CBT Practice'),
  officialQuiz('NLTC Official Quiz'),
  quickTest('Quick Tests'),
  live('Live Classes'),
  timetable('Timetable'),
  mockExams('Mock Exams'),
  leaderboard('Leaderboard'),
  announcements('Announcements'),
  blog('Blog'),
  notes('Study Notes'),
  settings('Settings'),
  bece('BECE Practice'),
  chat('Messages');

  const DashboardView(this.title);

  /// What the topbar shows while this view is open.
  final String title;
}

/// Which dashboard view is showing, and how the student got there.
///
/// Lifted out of the shell's own State so any card can navigate — the web
/// equivalent is the `view` useState in `DashboardPage`, passed down as `onNav`.
class DashboardController extends ChangeNotifier {
  DashboardView _view = DashboardView.home;

  /// Views that keep exam state while mounted are rebuilt from scratch on every
  /// visit, so a half-finished quiz is never resumed by accident. The web does
  /// this with a `navSeq` counter feeding React's `key`; here the counter feeds
  /// a [ValueKey] on the same views.
  static const _statefulViews = {
    DashboardView.officialQuiz,
    DashboardView.quickTest,
  };

  final Map<DashboardView, int> _visitCounts = {};

  /// Set when a push notification or deep link asked for a specific chat.
  /// Read once by ChatView, then cleared.
  String? _pendingChatId;

  DashboardView get view => _view;

  String? get pendingChatId => _pendingChatId;

  /// Bumped each time a stateful view is navigated to — see [_statefulViews].
  int visitCount(DashboardView view) => _visitCounts[view] ?? 0;

  void select(DashboardView view) {
    if (_statefulViews.contains(view)) {
      _visitCounts[view] = (_visitCounts[view] ?? 0) + 1;
    } else if (view == _view) {
      return;
    }
    _view = view;
    notifyListeners();
  }

  /// Opens Messages on a specific conversation — used when a chat push is
  /// tapped, mirroring the web's `?view=chat&chatId=` deep link.
  void openChat(String? chatId) {
    _pendingChatId = chatId;
    _view = DashboardView.chat;
    notifyListeners();
  }

  void consumePendingChatId() => _pendingChatId = null;

  /// Back to the dashboard, with visit counters cleared — used after signing out
  /// and back in, so the next student on a shared phone starts fresh.
  void reset() {
    _view = DashboardView.home;
    _visitCounts.clear();
    _pendingChatId = null;
    notifyListeners();
  }
}
