import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/live_session.dart';
import '../services/api_client.dart';

/// An Agora channel grant: what to join, as whom.
class AgoraGrant {
  const AgoraGrant({
    required this.appId,
    required this.channel,
    required this.token,
    required this.uid,
  });

  final String appId;
  final String channel;
  final String token;

  /// The numeric uid the backend derived from the Firebase uid. Stable per
  /// account, which is what lets presence in Firestore be matched to a speaker
  /// in the channel.
  final int uid;

  factory AgoraGrant.fromJson(String channel, Map<String, dynamic> json) =>
      AgoraGrant(
        appId: (json['appId'] ?? '').toString(),
        channel: (json['channelName'] ?? channel).toString(),
        token: (json['token'] ?? '').toString(),
        uid: json['uid'] is num ? (json['uid'] as num).toInt() : 0,
      );

  bool get isUsable => appId.isNotEmpty && token.isNotEmpty;
}

/// Live classes: the timetable, the room, and everything said in it.
///
/// The room's whole state lives in one Firestore document (`liveSessions/{id}`)
/// with a `messages` subcollection beside it, exactly as the website's
/// LivestreamPage uses it. That is deliberate: a student joining from the app and
/// one joining from a browser are in the same room, see the same chat, and put
/// their hands up in the same map. The rules let a student write only their own
/// key of `viewers` and `raisedHands`, which is what makes this safe.
class LiveRepository {
  LiveRepository({required ApiClient api, FirebaseFirestore? firestore})
      : _api = api,
        _db = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _session(String id) =>
      _db.collection('liveSessions').doc(id);

  CollectionReference<Map<String, dynamic>> _messages(String id) =>
      _session(id).collection('messages');

  // ─── The timetable ────────────────────────────────────────────────────────

  /// Every session this student may see, newest first.
  ///
  /// Filtering by audience happens here rather than in the query: `audience` is
  /// absent on older documents, and a Firestore inequality would drop them.
  Stream<List<LiveSession>> watchSessions({
    required bool isJunior,
    int limit = 20,
  }) =>
      _db.collection('liveSessions').snapshots().map((snap) {
        final sessions = snap.docs
            .map((d) => LiveSession.fromMap(d.id, d.data()))
            .where((s) => s.isVisibleTo(isJunior: isJunior))
            .toList()
          ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
        return sessions.take(limit).toList();
      });

  /// The live sessions right now — what the dashboard banner reads.
  Future<LiveSession?> currentlyLive({required bool isJunior}) async {
    try {
      final snap = await _db
          .collection('liveSessions')
          .where('status', isEqualTo: 'live')
          .limit(5)
          .get();
      final matches = snap.docs
          .map((d) => LiveSession.fromMap(d.id, d.data()))
          .where((s) => s.isVisibleTo(isJunior: isJunior));
      return matches.isEmpty ? null : matches.first;
    } catch (_) {
      return null;
    }
  }

  Stream<LiveSession?> watchSession(String id) => _session(id).snapshots().map(
        (snap) =>
            snap.exists ? LiveSession.fromMap(snap.id, snap.data() ?? {}) : null,
      );

  // ─── Joining ──────────────────────────────────────────────────────────────

  /// Asks the backend for an audience token on [channel].
  ///
  /// Students only ever get `audience`; the host role is refused to anyone who
  /// isn't an admin or teacher, which is enforced server-side.
  Future<AgoraGrant> audienceToken(String channel) async {
    final data = await _api.post('/agora/token', {
      'channelName': channel,
      'role': 'audience',
    });
    final grant = AgoraGrant.fromJson(channel, data);
    if (!grant.isUsable) {
      throw const ApiException('The class did not return a valid access token.');
    }
    return grant;
  }

  // ─── Presence ─────────────────────────────────────────────────────────────

  /// Writes this student into the room's headcount.
  ///
  /// One key of the `viewers` map, keyed by Firebase uid — the only shape the
  /// rules permit a student to write, and the shape the website's gallery reads.
  Future<void> enter(
    String sessionId, {
    required String uid,
    required String name,
    required int agoraUid,
    bool camera = false,
    bool microphone = false,
  }) async {
    await _session(sessionId).update({
      'viewers.$uid': {
        'name': name,
        'agoraUid': agoraUid,
        'cam': camera,
        'mic': microphone,
        'screen': false,
        'role': 'student',
      },
    });
  }

  /// Updates the flags on an existing presence entry — a student turning their
  /// microphone on after being invited to speak.
  Future<void> updatePresence(
    String sessionId, {
    required String uid,
    required String name,
    required int agoraUid,
    required bool camera,
    required bool microphone,
  }) =>
      enter(
        sessionId,
        uid: uid,
        name: name,
        agoraUid: agoraUid,
        camera: camera,
        microphone: microphone,
      );

  /// Removes this student from the headcount and drops any raised hand.
  ///
  /// Two writes rather than one: the rules validate the affected keys per field,
  /// and a combined delete of both maps is rejected on some rule versions.
  /// Failures are swallowed — this runs on the way out of the screen, and a
  /// stale viewer entry is a cosmetic problem the host can clear.
  Future<void> leave(String sessionId, String uid) async {
    final ref = _session(sessionId);
    try {
      await ref.update({'viewers.$uid': FieldValue.delete()});
    } catch (_) {/* already gone, or offline */}
    try {
      await ref.update({'raisedHands.$uid': FieldValue.delete()});
    } catch (_) {/* nothing raised */}
  }

  // ─── Taking part ──────────────────────────────────────────────────────────

  /// Raises or lowers this student's hand.
  Future<void> setHandRaised(
    String sessionId, {
    required String uid,
    required String name,
    required bool raised,
  }) =>
      _session(sessionId).update({
        'raisedHands.$uid': raised ? name : FieldValue.delete(),
      });

  /// Votes in the open poll. One vote per student, and changing it overwrites.
  Future<void> votePoll(
    String sessionId, {
    required String uid,
    required int optionIndex,
  }) =>
      _session(sessionId).update({'poll.votes.$uid': optionIndex});

  Stream<List<LiveMessage>> watchMessages(String sessionId, {int limit = 200}) =>
      _messages(sessionId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => LiveMessage.fromMap(d.id, d.data()))
                .toList()
                .reversed
                .toList(),
          );

  Future<void> sendMessage(
    String sessionId, {
    required String uid,
    required String name,
    required String text,
  }) async {
    final body = text.trim();
    if (body.isEmpty) return;
    await _messages(sessionId).add({
      'uid': uid,
      'name': name,
      'text': body,
      'role': 'student',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks this student as typing, so the room shows it the way the web does.
  Future<void> setTyping(
    String sessionId, {
    required String uid,
    required String name,
    required bool typing,
  }) async {
    try {
      await _session(sessionId).update({
        'typing.$uid': typing ? name : FieldValue.delete(),
      });
    } catch (_) {
      // A typing indicator is never worth surfacing an error for.
    }
  }

  /// The tutor's whiteboard strokes for the page currently on screen.
  Stream<List<Map<String, dynamic>>> watchWhiteboard(
    String sessionId,
    int page,
  ) =>
      _session(sessionId).collection('whiteboard').snapshots().map(
            (snap) => snap.docs
                .map((d) => d.data())
                .where((s) => (s['page'] as num?)?.toInt() == page)
                .toList(),
          );
}
