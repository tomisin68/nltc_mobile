import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/app_notification.dart';

void main() {
  group('AppNotification.fromApi', () {
    test('reads the shape GET /notifications/me returns', () {
      final notification = AppNotification.fromApi({
        'id': 'abc123',
        'title': 'New blog post',
        'body': 'Read the latest study tips.',
        'type': 'blog_published',
        'data': {'url': '/blog/study-tips'},
        'createdAt': '2026-03-12T09:30:00.000Z',
        'read': false,
      });

      expect(notification.id, 'abc123');
      expect(notification.title, 'New blog post');
      expect(notification.category, 'blog_published');
      expect(notification.route, '/blog/study-tips');
      expect(notification.read, isFalse);
      expect(notification.createdAt.toUtc().year, 2026);
    });

    test('a missing title falls back rather than rendering a blank row', () {
      final notification = AppNotification.fromApi({
        'id': 'abc',
        'body': 'Something happened.',
      });

      expect(notification.title, 'Notification');
      expect(notification.category, isNull);
      expect(notification.route, isNull);
    });

    test('a null createdAt is treated as now, not as the epoch', () {
      final before = DateTime.now().subtract(const Duration(seconds: 5));
      final notification = AppNotification.fromApi({'id': 'abc'});

      expect(notification.createdAt.isAfter(before), isTrue);
    });
  });

  group('AppNotification.fromPush', () {
    test('normalises an FCM payload into the same shape', () {
      final notification = AppNotification.fromPush(
        id: 'msg-1',
        title: 'Class starting',
        body: 'Your Physics class begins in 10 minutes.',
        data: const {'type': 'class_reminder', 'url': '/live'},
      );

      expect(notification.id, 'msg-1');
      expect(notification.category, 'class_reminder');
      expect(notification.route, '/live');
      expect(notification.read, isFalse);
    });

    test('a data-only push still produces a readable entry', () {
      final notification = AppNotification.fromPush(id: 'msg-2');

      expect(notification.title, 'NLTC Online');
      expect(notification.body, isEmpty);
    });
  });

  test('survives the SQLite row mapping unchanged', () {
    final original = AppNotification.fromApi({
      'id': 'abc123',
      'title': 'Payment received',
      'body': 'Your subscription is active.',
      'type': 'payment',
      'data': {'url': '/account'},
      'createdAt': 1773000000000,
      'read': true,
    });

    final restored = AppNotification.fromRow(original.toRow());

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.body, original.body);
    expect(restored.category, 'payment');
    expect(restored.route, '/account');
    expect(restored.read, isTrue);
    expect(restored.createdAt, original.createdAt);
  });

  test('copyWith only moves the read flag', () {
    final original = AppNotification.fromPush(id: 'msg-3', title: 'Hello');
    final read = original.copyWith(read: true);

    expect(read.read, isTrue);
    expect(read.id, original.id);
    expect(read.title, original.title);
    expect(read.createdAt, original.createdAt);
  });
}
