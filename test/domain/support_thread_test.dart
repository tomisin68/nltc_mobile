import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/support_thread.dart';

/// The support documents are written by two different codebases — this app and
/// the website's `SupportWidget` — into one collection an admin reads. The field
/// names and the topic ids are the contract between them, so they are pinned
/// here rather than left to whichever screen happens to render them.
void main() {
  group('SupportThread.fromMap', () {
    test('reads a thread the website wrote', () {
      final thread = SupportThread.fromMap('uid-1', {
        'uid': 'uid-1',
        'status': 'open',
        'topic': 'payment',
        'lastMessage': {'text': 'Any news?', 'senderRole': 'student'},
        'lastActivity': DateTime(2026, 8, 4, 9, 30).millisecondsSinceEpoch,
        'unreadForStudent': 2,
        'unreadForAdmin': 0,
      });

      expect(thread.uid, 'uid-1');
      expect(thread.status, SupportStatus.open);
      expect(thread.isResolved, isFalse);
      expect(thread.topic, 'payment');
      expect(thread.lastMessage, 'Any news?');
      expect(thread.lastActivity, DateTime(2026, 8, 4, 9, 30));
      expect(thread.unreadForStudent, 2);
    });

    test('falls back to the document id, which is the uid', () {
      expect(SupportThread.fromMap('uid-2', const {}).uid, 'uid-2');
    });

    test('anything that is not "resolved" is still open', () {
      expect(
        SupportThread.fromMap('u', const {'status': 'resolved'}).isResolved,
        isTrue,
      );
      expect(
        SupportThread.fromMap('u', const {'status': 'waiting'}).isResolved,
        isFalse,
      );
      expect(SupportThread.fromMap('u', const {}).isResolved, isFalse);
    });

    test('a thread filed before the topic picker existed has no topic', () {
      expect(SupportThread.fromMap('u', const {'topic': ''}).topic, isNull);
      expect(SupportThread.fromMap('u', const {}).topic, isNull);
    });

    test('a missing unread count reads as nothing waiting', () {
      final thread = SupportThread.fromMap('u', const {});
      expect(thread.unreadForStudent, 0);
      expect(thread.unreadForAdmin, 0);
    });
  });

  group('SupportMessage.fromMap', () {
    test('tells the two sides apart by senderRole', () {
      final fromAdmin = SupportMessage.fromMap('m1', const {
        'text': 'We have credited your account.',
        'senderRole': 'admin',
        'senderName': 'NLTC Admin',
      });
      final fromStudent = SupportMessage.fromMap('m2', const {
        'text': 'Thank you!',
        'senderRole': 'student',
      });

      expect(fromAdmin.fromAdmin, isTrue);
      expect(fromAdmin.senderName, 'NLTC Admin');
      expect(fromStudent.fromAdmin, isFalse);
    });

    test('a message the server has not stamped yet has no time', () {
      expect(SupportMessage.fromMap('m', const {'text': 'hi'}).createdAt, isNull);
    });
  });

  group('SupportTopic', () {
    test('ids match the website, so the admin inbox labels them', () {
      expect(
        SupportTopic.values.map((t) => t.id),
        containsAll(<String>[
          'payment',
          'access',
          'lessons',
          'cbt',
          'live',
          'technical',
          'other',
        ]),
      );
    });

    test('labelFor resolves a stored id', () {
      expect(SupportTopic.labelFor('payment'), 'Payment & fees');
    });

    test('an id from a newer website build still reads sensibly', () {
      expect(SupportTopic.labelFor('refunds'), 'Support request');
      expect(SupportTopic.labelFor(null), 'Support request');
    });
  });
}
