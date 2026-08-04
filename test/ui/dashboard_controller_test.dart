import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/ui/core/state/dashboard_controller.dart';

void main() {
  group('DashboardController', () {
    test('opens on the dashboard', () {
      expect(DashboardController().view, DashboardView.home);
    });

    test('selecting a view notifies once', () {
      final controller = DashboardController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.select(DashboardView.lessons);

      expect(controller.view, DashboardView.lessons);
      expect(notifications, 1);
    });

    test('re-selecting the current view is a no-op', () {
      final controller = DashboardController();
      controller.select(DashboardView.lessons);

      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.select(DashboardView.lessons);

      expect(notifications, 0);
    });

    test('re-selecting a stateful exam view rebuilds it', () {
      // Quick Tests and the Official Quiz hold a part-finished attempt, so
      // navigating to one you are already on has to tear it down — otherwise a
      // student who taps away and back resumes a test they meant to restart.
      final controller = DashboardController();

      controller.select(DashboardView.quickTest);
      final first = controller.visitCount(DashboardView.quickTest);

      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.select(DashboardView.quickTest);

      expect(controller.visitCount(DashboardView.quickTest), first + 1);
      expect(notifications, 1, reason: 'the view must be rebuilt');
    });

    test('a plain view is not given a rebuild counter', () {
      final controller = DashboardController();
      controller.select(DashboardView.leaderboard);
      controller.select(DashboardView.home);
      controller.select(DashboardView.leaderboard);

      expect(controller.visitCount(DashboardView.leaderboard), 0);
    });

    test('openChat lands on Messages carrying the conversation id', () {
      final controller = DashboardController();

      controller.openChat('chat-42');

      expect(controller.view, DashboardView.chat);
      expect(controller.pendingChatId, 'chat-42');
    });

    test('the pending chat id is consumed so it cannot reopen later', () {
      final controller = DashboardController();
      controller.openChat('chat-42');

      controller.consumePendingChatId();

      expect(controller.pendingChatId, isNull);
    });

    test('reset clears the view, counters and pending chat', () {
      // Sign-out wipes on-device data; the next student on a shared phone must
      // not land on the previous one's view or resume their test.
      final controller = DashboardController();
      controller.select(DashboardView.quickTest);
      controller.openChat('chat-42');

      controller.reset();

      expect(controller.view, DashboardView.home);
      expect(controller.pendingChatId, isNull);
      expect(controller.visitCount(DashboardView.quickTest), 0);
    });

    test('every view carries the title the web topbar shows', () {
      // Same names, same places — a student moving between app and website
      // should not have to relearn the product.
      expect(DashboardView.home.title, 'Dashboard');
      expect(DashboardView.cbt.title, 'CBT Practice');
      expect(DashboardView.officialQuiz.title, 'NLTC Official Quiz');
      expect(DashboardView.mockExams.title, 'Mock Exams');
      expect(DashboardView.bece.title, 'BECE Practice');
      expect(DashboardView.chat.title, 'Messages');
      expect(DashboardView.announcements.title, 'Announcements');

      for (final view in DashboardView.values) {
        expect(view.title, isNotEmpty, reason: '${view.name} needs a title');
      }
    });
  });
}
