import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/chat.dart';

/// What the people-picker searches over, and in what order it offers them.
///
/// The picker only ever filters on what these two produce, so a name that this
/// says does not match is a person the student cannot start a conversation with.
void main() {
  ChatContact person(
    String name, {
    String? email,
    String role = 'student',
  }) =>
      ChatContact(uid: name, name: name, email: email, role: role);

  group('ChatContact.matches', () {
    test('finds a surname typed on its own', () {
      expect(person('Ada Okafor').matches('okafor'), isTrue);
    });

    test('finds a first name typed on its own', () {
      expect(person('Ada Okafor').matches('ada'), isTrue);
    });

    test('matches part-way through a name, not only the start', () {
      expect(person('Ada Okafor').matches('kafo'), isTrue);
    });

    test('ignores the case the name happens to be stored in', () {
      expect(person('ADA OKAFOR').matches('ada'), isTrue);
    });

    test('matches on the email, for a classmate whose spelling is a guess', () {
      expect(
        person('Ada Okafor', email: 'ada.o@example.com').matches('ada.o'),
        isTrue,
      );
    });

    test('someone with no email is not a crash', () {
      expect(person('Ada Okafor').matches('example'), isFalse);
    });

    test('says no when it means no', () {
      expect(person('Ada Okafor').matches('chidi'), isFalse);
    });
  });

  group('ChatContact.compare', () {
    test('tutors come first, whatever their name', () {
      final sorted = [
        person('Zainab Bello'),
        person('Mr Adeyemi', role: 'teacher'),
        person('Ada Okafor'),
      ]..sort(ChatContact.compare);

      expect(sorted.map((c) => c.name), [
        'Mr Adeyemi',
        'Ada Okafor',
        'Zainab Bello',
      ]);
    });

    test('admins rank with tutors, not with students', () {
      final sorted = [
        person('Ada Okafor'),
        person('Zainab Bello', role: 'admin'),
      ]..sort(ChatContact.compare);

      expect(sorted.first.name, 'Zainab Bello');
    });

    test('students are alphabetical regardless of stored capitalisation', () {
      final sorted = [
        person('chidi Nwosu'),
        person('Ada Okafor'),
        person('Bola Adeyemi'),
      ]..sort(ChatContact.compare);

      expect(sorted.map((c) => c.name), [
        'Ada Okafor',
        'Bola Adeyemi',
        'chidi Nwosu',
      ]);
    });
  });

  group('ChatContact.fromMap', () {
    test('builds the name from the parts the website writes', () {
      final contact = ChatContact.fromMap('u1', const {
        'firstName': 'Ada',
        'lastName': 'Okafor',
        'email': 'ada@example.com',
      });
      expect(contact.name, 'Ada Okafor');
      expect(contact.email, 'ada@example.com');
    });

    test('falls back to displayName, then to the email itself', () {
      expect(
        ChatContact.fromMap('u1', const {'displayName': 'ada.o'}).name,
        'ada.o',
      );
      expect(
        ChatContact.fromMap('u1', const {'email': 'ada@example.com'}).name,
        'ada@example.com',
      );
    });

    test('an account with nothing on it is still listable', () {
      final contact = ChatContact.fromMap('u1', const {});
      expect(contact.name, 'Student');
      expect(contact.email, isNull);
      expect(contact.isTutor, isFalse);
    });

    test('carries presence through, so the picker can show a dot', () {
      final contact = ChatContact.fromMap('u1', {
        'online': true,
        // Both halves: the flag on its own is a claim somebody's last living
        // moment made, and says nothing about now.
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      });
      expect(contact.presence.isOnline, isTrue);
    });

    test('a stale flag does not put a green dot in the picker', () {
      final contact = ChatContact.fromMap('u1', {
        'online': true,
        'lastSeen': DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      });
      expect(contact.presence.isOnline, isFalse);
    });
  });
}
