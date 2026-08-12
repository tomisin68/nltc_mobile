import 'app_notification.dart';

/// The buckets the notification inbox can be narrowed to.
///
/// Grouped by what a student came looking for rather than by the backend's
/// `type` string: somebody hunting for a message does not know or care that the
/// server calls it `chat_message`, and a payment can arrive as any of three
/// different types depending on which way it was settled. Every type the
/// backend emits belongs to exactly one bucket, and [other] catches whatever it
/// starts emitting next — a new category is never invisible, it just lands in
/// the bucket that makes no promises.
enum NotificationFilter {
  all('All'),
  messages('Messages'),
  announcements('Announcements'),
  live('Live'),
  lessons('Lessons'),
  payments('Payments'),
  other('Other');

  const NotificationFilter(this.label);

  /// What the chip says.
  final String label;

  /// Backend `type` values that belong to each bucket.
  ///
  /// Older names are kept alongside the current ones because rows already
  /// sitting in a student's inbox were written under whatever the backend
  /// called them at the time.
  static const _types = <NotificationFilter, Set<String>>{
    NotificationFilter.messages: {'chat_message', 'group_invite'},
    NotificationFilter.announcements: {
      'announcement',
      'center_announcement_alert',
    },
    NotificationFilter.live: {
      'live_class_start',
      'session_ended',
      'class_reminder',
      'live_class',
    },
    NotificationFilter.lessons: {
      'new_lesson',
      'new_blog',
      'blog_published',
    },
    NotificationFilter.payments: {
      'payment',
      'payment_approved',
      'payment_rejected',
      'payment_proof',
      'subscription',
    },
  };

  /// Every named bucket, which is to say everything [other] is the absence of.
  static final Set<String> _claimed = {
    for (final types in _types.values) ...types,
  };

  bool matches(AppNotification notification) => switch (this) {
        NotificationFilter.all => true,
        NotificationFilter.other =>
          !_claimed.contains(notification.category ?? ''),
        _ => _types[this]!.contains(notification.category ?? ''),
      };

  /// The chips worth showing for [items].
  ///
  /// "All" is always there; the rest earn their place by having something in
  /// them. A row of seven chips where five are dead ends is worse than no
  /// filtering at all, and which ones are live differs wildly between a student
  /// who chats all day and one who never opens Messages.
  static List<NotificationFilter> available(List<AppNotification> items) => [
        NotificationFilter.all,
        for (final filter in NotificationFilter.values)
          if (filter != NotificationFilter.all &&
              items.any(filter.matches))
            filter,
      ];
}
