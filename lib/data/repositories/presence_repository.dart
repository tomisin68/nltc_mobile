import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/user_presence.dart';

/// Who is online, on `users/{uid}`.
///
/// The same two fields the website's `usePresence` hook owns — `online` and
/// `lastSeen` — which the Firestore rules list in `validProfileUpdate()`, so a
/// student may write them on their own document and read anyone else's.
///
/// Reads are per-uid document streams rather than one query: the rules allow any
/// signed-in user to read `users`, but a `whereIn` over the people in a chat list
/// caps at thirty and re-runs the whole query when one of them so much as blinks.
class PresenceRepository {
  PresenceRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);

  Stream<UserPresence> watch(String uid) => _user(uid).snapshots().map(
        (snap) => snap.exists
            ? UserPresence.fromMap(snap.data() ?? const {})
            : UserPresence.unknown,
      );

  /// Marks this student as here, refreshing `lastSeen` as it goes.
  ///
  /// Best-effort throughout: presence is a courtesy to the other side of the
  /// conversation, and a student with no signal has bigger problems than a dot.
  Future<void> setOnline(String uid) => _write(uid, online: true);

  /// Marks this student as away.
  ///
  /// Called on the way into the background and on sign-out. Without it the flag
  /// stays true until the three-minute `lastSeen` window closes, and the person
  /// waiting on a reply sees a green dot on someone who has put their phone down.
  Future<void> setOffline(String uid) => _write(uid, online: false);

  Future<void> _write(String uid, {required bool online}) async {
    try {
      await _user(uid).update({
        'online': online,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Offline, or the document has not been created yet — either way there is
      // nothing useful to tell the student.
    }
  }
}
