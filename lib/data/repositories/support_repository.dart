import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/app_user.dart';
import '../../domain/models/support_thread.dart';

/// The student's side of the help desk — `supportThreads/{uid}`.
///
/// Reads and writes the same documents the website's `SupportWidget` does, so a
/// conversation started in a browser carries on in the app and the admin sees
/// one thread per student either way. Deliberately not built on
/// [ChatRepository]: support has to work for an account that is locked out, and
/// Messages is not one of the free views.
///
/// Every student-side write obeys two rules that are easy to trip over, both
/// enforced by `validStudentSupportUpdate()` in `firestore.rules`:
///
///  * the update is a `hasOnly()` allowlist, so a field not on it rejects the
///    whole write; and
///  * the result must leave `unreadForStudent` at zero. A patch that only sets
///    `status` is refused whenever a reply is sitting unread, which is why
///    every method here writes the counter alongside whatever it came to say.
class SupportRepository {
  SupportRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// The ceiling `validSupportMessage()` enforces.
  static const maxMessageLength = 2000;

  /// How much of a message goes into the thread's summary line.
  static const _previewLength = 140;

  DocumentReference<Map<String, dynamic>> _thread(String uid) =>
      _db.collection('supportThreads').doc(uid);

  CollectionReference<Map<String, dynamic>> _messages(String uid) =>
      _thread(uid).collection('messages');

  /// The student's thread, or null if they have never asked for help.
  ///
  /// Kept live for the whole session rather than only while the panel is open:
  /// it is one document, and it is what the unread badge on the help button is
  /// drawn from.
  Stream<SupportThread?> watchThread(String uid) => _thread(uid).snapshots().map(
        (snap) => snap.exists
            ? SupportThread.fromMap(snap.id, snap.data() ?? const {})
            : null,
      );

  Stream<List<SupportMessage>> watchMessages(String uid) => _messages(uid)
      .orderBy('createdAt')
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => SupportMessage.fromMap(d.id, d.data()))
            .toList(growable: false),
      );

  /// Posts a message, opening the thread if this is the first one.
  ///
  /// [topic] is only read when the thread is being created — an existing
  /// request keeps the subject it was filed under. A message on a resolved
  /// thread reopens it, which is what the student is told on the closing note.
  Future<void> sendMessage({
    required String uid,
    required AppUser? profile,
    required String email,
    required String name,
    required String text,
    required SupportThread? thread,
    SupportTopic? topic,
  }) async {
    final body = text.trim();
    if (body.isEmpty) return;
    if (body.length > maxMessageLength) {
      throw ArgumentError('Support messages are capped at $maxMessageLength characters');
    }

    final preview = body.length > _previewLength
        ? '${body.substring(0, _previewLength - 3)}…'
        : body;
    final last = {
      'text': preview,
      'senderRole': 'student',
      'timestamp': FieldValue.serverTimestamp(),
    };

    if (thread == null) {
      // The contact details ride along on the thread so the admin can triage —
      // and reach a student by phone — without opening a second screen.
      await _thread(uid).set({
        'uid': uid,
        'studentName': name,
        'studentEmail': email,
        'studentPhone': profile?.phone ?? '',
        'studentPhoto': profile?.photoUrl,
        'studentMode': profile?.studentMode ?? 'online',
        'targetExam': profile?.targetExam ?? '',
        'center': profile?.center ?? '',
        'topic': (topic ?? SupportTopic.other).id,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'lastActivity': FieldValue.serverTimestamp(),
        'lastMessage': last,
        'unreadForAdmin': 1,
        'unreadForStudent': 0,
      });
    } else {
      await _thread(uid).update({
        'status': 'open', // a new message reopens a resolved request
        'lastActivity': FieldValue.serverTimestamp(),
        'lastMessage': last,
        'unreadForAdmin': FieldValue.increment(1),
        'unreadForStudent': 0,
        'studentName': name,
      });
    }

    await _messages(uid).add({
      'text': body,
      'senderRole': 'student',
      'senderId': uid,
      'senderName': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Clears the student's unread count — opening the panel is reading the reply.
  Future<void> markRead(String uid) async {
    try {
      await _thread(uid).update({'unreadForStudent': 0});
    } catch (_) {
      // Never worth an error in front of somebody who came here for help.
    }
  }

  /// Marks the request solved. Sending again reopens it.
  Future<void> markSolved(String uid) => _thread(uid).update({
        'status': 'resolved',
        'lastActivity': FieldValue.serverTimestamp(),
        // Required by the rules, and true by construction: the panel is open.
        'unreadForStudent': 0,
      });
}
