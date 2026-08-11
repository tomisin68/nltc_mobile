import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/app_notification.dart';
import 'package:nltc/domain/models/notification_filter.dart';

AppNotification _of(String? type, {String? url}) => AppNotification.fromApi({
      'id': '$type-${url ?? ''}',
      'title': 'Something happened',
      'type': type,
      if (url != null) 'data': {'url': url},
    });

void main() {
  group('NotificationFilter.matches', () {
    test('All takes everything, including a type nobody has named yet', () {
      expect(NotificationFilter.all.matches(_of('chat_message')), isTrue);
      expect(NotificationFilter.all.matches(_of('brand_new_type')), isTrue);
      expect(NotificationFilter.all.matches(_of(null)), isTrue);
    });

    test('a payment is a payment however it was settled', () {
      for (final type in [
        'payment',
        'payment_approved',
        'payment_rejected',
        'payment_proof',
        'subscription',
      ]) {
        expect(
          NotificationFilter.payments.matches(_of(type)),
          isTrue,
          reason: '$type should sit under Payments',
        );
      }
      expect(NotificationFilter.payments.matches(_of('chat_message')), isFalse);
    });

    test('the live bucket covers reminders as well as classes going on air', () {
      expect(NotificationFilter.live.matches(_of('class_reminder')), isTrue);
      expect(NotificationFilter.live.matches(_of('live_class_start')), isTrue);
      expect(NotificationFilter.live.matches(_of('session_ended')), isTrue);
    });

    test('Other is exactly what no named bucket claimed', () {
      expect(NotificationFilter.other.matches(_of('welcome')), isTrue);
      expect(NotificationFilter.other.matches(_of('inactivity_nudge')), isTrue);
      expect(NotificationFilter.other.matches(_of(null)), isTrue);
      expect(NotificationFilter.other.matches(_of('chat_message')), isFalse);
      expect(NotificationFilter.other.matches(_of('new_lesson')), isFalse);
    });

    test('every bucket claims a type exactly once', () {
      const types = [
        'chat_message',
        'announcement',
        'center_announcement_alert',
        'live_class_start',
        'session_ended',
        'class_reminder',
        'new_lesson',
        'new_blog',
        'payment_approved',
        'welcome',
      ];

      for (final type in types) {
        final owners = NotificationFilter.values
            .where((f) => f != NotificationFilter.all && f.matches(_of(type)))
            .toList();
        expect(owners, hasLength(1), reason: '$type landed in $owners');
      }
    });
  });

  group('NotificationFilter.available', () {
    test('offers only the buckets with something in them', () {
      final chips = NotificationFilter.available([
        _of('chat_message'),
        _of('announcement'),
      ]);

      expect(chips, [
        NotificationFilter.all,
        NotificationFilter.messages,
        NotificationFilter.announcements,
      ]);
    });

    test('an empty inbox still offers All and nothing else', () {
      expect(NotificationFilter.available(const []), [NotificationFilter.all]);
    });
  });

  group('AppNotification.chatId', () {
    test('is read out of the deep link the backend attaches', () {
      final notification = _of(
        'chat_message',
        url: '/dashboard?view=chat&chatId=abc123',
      );

      expect(notification.chatId, 'abc123');
    });

    test('reads the absolute form the push payload carries too', () {
      final notification = _of(
        'chat_message',
        url: 'https://nltc.com.ng/dashboard?view=chat&chatId=xyz789',
      );

      expect(notification.chatId, 'xyz789');
    });

    test('is null for anything that is not a message', () {
      final announcement = _of(
        'announcement',
        url: '/dashboard?view=chat&chatId=abc123',
      );

      expect(announcement.chatId, isNull);
    });

    test('is null when the link carries no chat', () {
      expect(_of('chat_message', url: '/dashboard?view=chat').chatId, isNull);
      expect(_of('chat_message').chatId, isNull);
    });
  });
}
