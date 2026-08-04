import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/user_presence.dart';

/// Being shown as online when you are not is worse than the reverse: somebody
/// waiting on an answer reads a green dot as "they are ignoring me". Both halves
/// of the record therefore have to agree before anyone is called present.
void main() {
  UserPresence at(Duration ago, {bool online = false}) => UserPresence(
        online: online,
        lastSeen: DateTime.now().subtract(ago),
      );

  group('UserPresence.isOnline', () {
    test('the flag and a fresh sighting together mean present', () {
      expect(at(const Duration(seconds: 30), online: true).isOnline, isTrue);
      expect(at(const Duration(minutes: 2), online: true).isOnline, isTrue);
    });

    test('a set flag expires with the sighting behind it', () {
      // An app killed from the task switcher, a phone that ran out of battery,
      // a browser force-quit: all three leave `online: true` behind for ever,
      // and the stamp is the only thing that ever contradicts it.
      expect(at(const Duration(minutes: 4), online: true).isOnline, isFalse);
      expect(at(const Duration(hours: 3), online: true).isOnline, isFalse);
      expect(at(const Duration(days: 1), online: true).isOnline, isFalse);
    });

    test('a cleared flag is believed at once, however recent the sighting', () {
      // Backgrounding the app writes `online: false` and a fresh `lastSeen` in
      // the same breath. Reading that as "seen seconds ago, so present" kept a
      // green dot on somebody who had just put their phone down.
      expect(at(const Duration(seconds: 5)).isOnline, isFalse);
      expect(at(const Duration(minutes: 2)).isOnline, isFalse);
    });

    test('a flag with no sighting at all proves nothing', () {
      expect(const UserPresence(online: true).isOnline, isFalse);
    });

    test('someone never seen at all is offline, not unknown-but-green', () {
      expect(UserPresence.unknown.isOnline, isFalse);
      expect(const UserPresence(lastSeen: null).isOnline, isFalse);
    });

    test('a clock skewed into the future counts as present, not absent', () {
      expect(
        UserPresence(
          online: true,
          lastSeen: DateTime.now().add(const Duration(minutes: 5)),
        ).isOnline,
        isTrue,
      );
    });

    test('the window matches the three minutes the website allows', () {
      expect(UserPresence.staleAfter, const Duration(minutes: 3));
    });
  });

  group('UserPresence.fromMap', () {
    test('prefers the name parts, as every other reader of users does', () {
      final presence = UserPresence.fromMap({
        'firstName': 'Ada',
        'lastName': 'Okafor',
        'displayName': 'ada.o',
        'online': true,
      });
      expect(presence.name, 'Ada Okafor');
      expect(presence.online, isTrue);
    });

    test('falls back to displayName when there are no name parts', () {
      expect(UserPresence.fromMap({'displayName': 'ada.o'}).name, 'ada.o');
    });

    test('reads either photo field, old documents included', () {
      expect(
        UserPresence.fromMap({'photoURL': 'https://x/y.png'}).photo,
        'https://x/y.png',
      );
      expect(
        UserPresence.fromMap({
          'profileImage': 'https://a/b.png',
          'photoURL': 'https://x/y.png',
        }).photo,
        'https://a/b.png',
      );
    });

    test('an empty document is nobody, not somebody online', () {
      final presence = UserPresence.fromMap(const {});
      expect(presence.online, isFalse);
      expect(presence.isOnline, isFalse);
      expect(presence.lastSeen, isNull);
    });
  });
}
