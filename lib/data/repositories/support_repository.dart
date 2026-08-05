import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/app_user.dart';
import '../../domain/models/support_thread.dart';

/// The student's side of the help desk — `supportThreads/{threadId}`.
///
/// Reads and writes the same documents the website's `SupportWidget` does, so a
/// conversation started in a browser carries on in the app and the admin sees
/// the same inbox either way. Deliberately not built on [ChatRepository]:
/// support has to work for an account that is locked out, and Messages is not
/// one of the free views.
///
/// A student holds MANY threads. Solving one closes it for good — the next
/// question opens a fresh conversation rather than reopening the old one, and
/// the closed ones stay readable as history. Ownership is therefore the `uid`
/// FIELD, not the document id, which is what [watchThreads] queries on.
/// Threads written before this carry the uid in both places, so they simply
/// load as that student's first conversation.
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

  CollectionReference<Map<String, dynamic>> get _threads =>
      _db.collection('supportThreads');

  DocumentReference<Map<String, dynamic>> _thread(String threadId) =>
      _threads.doc(threadId);

  CollectionReference<Map<String, dynamic>> _messages(String threadId) =>
      _thread(threadId).collection('messages');

  /// Every conversation this student has ever opened, newest first.
  ///
  /// Kept live for the whole session rather than only while the sheet is open:
  /// they are a handful of small documents, and their unread counts add up to
  /// the badge on the help button. Sorted here rather than in the query so no
  /// composite index has to be deployed for it.
  Stream<List<SupportThread>> watchThreads(String uid) => _threads
          .where('uid', isEqualTo: uid)
          .snapshots()
          .map((snap) {
        final threads = snap.docs
            .map((d) => SupportThread.fromMap(d.id, d.data()))
            .toList();
        threads.sort((a, b) {
          final at = a.lastActivity?.millisecondsSinceEpoch ?? 0;
          final bt = b.lastActivity?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
        });
        return threads;
      });

  Stream<List<SupportMessage>> watchMessages(String threadId) =>
      _messages(threadId).orderBy('createdAt').snapshots().map(
            (snap) => snap.docs
                .map((d) => SupportMessage.fromMap(d.id, d.data()))
                .toList(growable: false),
          );

  static String _preview(String body) => body.length > _previewLength
      ? '${body.substring(0, _previewLength - 3)}…'
      : body;

  /// Opens a brand-new conversation and files its first message.
  ///
  /// Returns the new thread's id so the caller can drop straight into it.
  Future<String> startThread({
    required String uid,
    required AppUser? profile,
    required String email,
    required String name,
    required String text,
    required SupportTopic topic,
  }) async {
    final body = text.trim();
    if (body.isEmpty) {
      throw ArgumentError('A support request needs a message');
    }
    if (body.length > maxMessageLength) {
      throw ArgumentError('Support messages are capped at $maxMessageLength characters');
    }

    // The contact details ride along on the thread so the admin can triage —
    // and reach a student by phone — without opening a second screen.
    final created = await _threads.add({
      'uid': uid,
      'studentName': name,
      'studentEmail': email,
      'studentPhone': profile?.phone ?? '',
      'studentPhoto': profile?.photoUrl,
      'studentMode': profile?.studentMode ?? 'online',
      'targetExam': profile?.targetExam ?? '',
      'center': profile?.center ?? '',
      'topic': topic.id,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'lastActivity': FieldValue.serverTimestamp(),
      'lastMessage': {
        'text': _preview(body),
        'senderRole': 'student',
        'timestamp': FieldValue.serverTimestamp(),
      },
      'unreadForAdmin': 1,
      'unreadForStudent': 0,
    });

    await _post(created.id, uid: uid, name: name, body: body);
    return created.id;
  }

  /// Posts a follow-up into a conversation that is already open.
  ///
  /// `status` rides along because an admin may have solved the request while
  /// the student was typing — that reply belongs in this thread, not a new one.
  Future<void> sendMessage({
    required String threadId,
    required String uid,
    required String name,
    required String text,
  }) async {
    final body = text.trim();
    if (body.isEmpty) return;
    if (body.length > maxMessageLength) {
      throw ArgumentError('Support messages are capped at $maxMessageLength characters');
    }

    await _thread(threadId).update({
      'status': 'open',
      'lastActivity': FieldValue.serverTimestamp(),
      'lastMessage': {
        'text': _preview(body),
        'senderRole': 'student',
        'timestamp': FieldValue.serverTimestamp(),
      },
      'unreadForAdmin': FieldValue.increment(1),
      'unreadForStudent': 0,
      'studentName': name,
    });

    await _post(threadId, uid: uid, name: name, body: body);
  }

  Future<void> _post(
    String threadId, {
    required String uid,
    required String name,
    required String body,
  }) =>
      _messages(threadId).add({
        'text': body,
        'senderRole': 'student',
        'senderId': uid,
        'senderName': name,
        'createdAt': FieldValue.serverTimestamp(),
      });

  /// Clears the student's unread count — opening a chat is reading the reply.
  Future<void> markRead(String threadId) async {
    try {
      await _thread(threadId).update({'unreadForStudent': 0});
    } catch (_) {
      // Never worth an error in front of somebody who came here for help.
    }
  }

  /// Closes the request. The next question starts a new conversation.
  Future<void> markSolved(String threadId) => _thread(threadId).update({
        'status': 'resolved',
        'lastActivity': FieldValue.serverTimestamp(),
        // Required by the rules, and true by construction: the sheet is open.
        'unreadForStudent': 0,
      });
}
