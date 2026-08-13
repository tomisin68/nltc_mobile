import 'app_user.dart' show tsToMs;

/// Where a class is in its life.
enum LiveStatus {
  scheduled,
  live,
  ended;

  static LiveStatus parse(String? raw) => switch (raw) {
        'live' => LiveStatus.live,
        'ended' => LiveStatus.ended,
        _ => LiveStatus.scheduled,
      };
}

/// One person in the room, as the session document records them.
///
/// Presence used to be a bare name string; the website normalises both shapes and
/// so does this, because old sessions are still in the collection.
class LiveViewer {
  const LiveViewer({
    required this.uid,
    required this.name,
    this.agoraUid,
    this.camera = false,
    this.microphone = false,
    this.sharingScreen = false,
    this.role = 'student',
  });

  final String uid;
  final String name;
  final int? agoraUid;
  final bool camera;
  final bool microphone;
  final bool sharingScreen;
  final String role;

  bool get isHost => role == 'host';

  factory LiveViewer.parse(String uid, dynamic value) {
    if (value is String) return LiveViewer(uid: uid, name: value);
    if (value is! Map) return LiveViewer(uid: uid, name: 'Student');
    return LiveViewer(
      uid: uid,
      name: (value['name'] ?? 'Student').toString(),
      agoraUid:
          value['agoraUid'] is num ? (value['agoraUid'] as num).toInt() : null,
      camera: value['cam'] == true,
      microphone: value['mic'] == true,
      sharingScreen: value['screen'] == true,
      role: (value['role'] ?? 'student').toString(),
    );
  }

  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }
}

/// A poll the tutor has put to the room.
class LivePoll {
  const LivePoll({
    required this.question,
    required this.options,
    required this.votes,
    required this.open,
  });

  final String question;
  final List<String> options;

  /// Firebase uid → chosen option index.
  final Map<String, int> votes;
  final bool open;

  int countFor(int optionIndex) =>
      votes.values.where((v) => v == optionIndex).length;

  int get totalVotes => votes.length;

  /// What this student picked, if they have.
  int? voteOf(String? uid) => uid == null ? null : votes[uid];

  static LivePoll? parse(dynamic value) {
    if (value is! Map) return null;
    final question = (value['question'] ?? '').toString();
    final options = value['options'] is List
        ? (value['options'] as List).map((o) => o.toString()).toList()
        : const <String>[];
    if (question.isEmpty || options.isEmpty) return null;

    final votes = <String, int>{};
    if (value['votes'] is Map) {
      (value['votes'] as Map).forEach((key, v) {
        if (v is num) votes[key.toString()] = v.toInt();
      });
    }
    return LivePoll(
      question: question,
      options: options,
      votes: votes,
      open: value['open'] != false,
    );
  }
}

/// A live class, as `liveSessions/{id}` describes it.
class LiveSession {
  const LiveSession({
    required this.id,
    required this.title,
    required this.channel,
    required this.status,
    this.subject,
    this.hostName,
    this.description,
    this.audience = 'all',
    this.scheduledAt,
    this.startedAt,
    this.createdAt,
    this.endedAt,
    this.viewers = const [],
    this.viewerCountField = 0,
    this.raisedHands = const {},
    this.mutedUids = const {},
    this.removedUids = const {},
    this.waitingRoom = const {},
    this.typing = const {},
    this.pinnedMessage,
    this.poll,
    this.featuredUid,
    this.hostAgoraUid,
    this.boardOpen = false,
    this.boardPage = 0,
  });

  final String id;
  final String title;

  /// The Agora channel name. Without it there is nothing to join.
  final String channel;

  final LiveStatus status;
  final String? subject;
  final String? hostName;
  final String? description;

  /// `all`, `bece` or `regular` — which cohort the class is for.
  final String audience;

  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? createdAt;
  final DateTime? endedAt;

  final List<LiveViewer> viewers;

  /// The tutor's own counter, kept for sessions that predate the viewers map.
  final int viewerCountField;

  /// Firebase uid → display name.
  final Map<String, String> raisedHands;

  /// Students the tutor has muted, kicked, or is holding outside the room.
  final Map<String, dynamic> mutedUids;
  final Map<String, dynamic> removedUids;
  final Map<String, dynamic> waitingRoom;

  final Map<String, String> typing;

  final String? pinnedMessage;
  final LivePoll? poll;

  /// The participant the tutor has pinned to everyone's stage.
  final String? featuredUid;

  /// The tutor's numeric Agora uid, so their stream can be told from a
  /// co-presenting student's.
  final int? hostAgoraUid;

  final bool boardOpen;
  final int boardPage;

  bool get isLive => status == LiveStatus.live;
  bool get isScheduled => status == LiveStatus.scheduled;
  bool get hasEnded => status == LiveStatus.ended;

  /// Prefer the presence map; fall back to the tutor's counter for old sessions.
  int get watching => viewers.isNotEmpty ? viewers.length : viewerCountField;

  /// Newest-first ordering, matching `getSessionTime` on the web.
  int get sortTime =>
      (createdAt ?? scheduledAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .millisecondsSinceEpoch;

  bool isVisibleTo({required bool isJunior}) => switch (audience) {
        'bece' => isJunior,
        'regular' => !isJunior,
        _ => true,
      };

  bool handRaisedBy(String? uid) => uid != null && raisedHands.containsKey(uid);
  bool isMuted(String? uid) => uid != null && mutedUids.containsKey(uid);
  bool wasRemoved(String? uid) => uid != null && removedUids.containsKey(uid);
  bool isWaiting(String? uid) => uid != null && waitingRoom.containsKey(uid);

  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  static DateTime? _date(dynamic v) {
    final ms = tsToMs(v);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const {};

  static Map<String, String> _stringMap(dynamic v) {
    if (v is! Map) return const {};
    final out = <String, String>{};
    v.forEach((key, value) => out[key.toString()] = value.toString());
    return out;
  }

  factory LiveSession.fromMap(String id, Map<String, dynamic> m) {
    final board = _map(m['board']);

    return LiveSession(
      id: id,
      title: _str(m['title']) ?? 'Live class',
      channel: _str(m['channel']) ?? _str(m['channelName']) ?? '',
      status: LiveStatus.parse(_str(m['status'])),
      subject: _str(m['subject']),
      hostName: _str(m['hostName']),
      description: _str(m['description']),
      audience: _str(m['audience']) ?? 'all',
      scheduledAt: _date(m['scheduledAt']),
      startedAt: _date(m['startedAt']) ?? _date(m['launchedAt']),
      createdAt: _date(m['createdAt']),
      endedAt: _date(m['endedAt']),
      viewers: [
        for (final entry in _map(m['viewers']).entries)
          LiveViewer.parse(entry.key, entry.value),
      ],
      viewerCountField:
          m['viewerCount'] is num ? (m['viewerCount'] as num).toInt() : 0,
      raisedHands: _stringMap(m['raisedHands']),
      mutedUids: {..._map(m['mutedUids']), ..._map(m['mutedUsers'])},
      removedUids: {..._map(m['removedUids']), ..._map(m['kickedUsers'])},
      waitingRoom: _map(m['waitingRoom']),
      typing: _stringMap(m['typing']),
      pinnedMessage: _str(m['pinnedMessage']),
      poll: LivePoll.parse(m['poll']),
      featuredUid: _str(m['featuredUid']),
      hostAgoraUid:
          m['hostAgoraUid'] is num ? (m['hostAgoraUid'] as num).toInt() : null,
      boardOpen: board['open'] == true,
      boardPage: board['page'] is num ? (board['page'] as num).toInt() : 0,
    );
  }
}

/// One line of class chat.
class LiveMessage {
  const LiveMessage({
    required this.id,
    required this.name,
    required this.text,
    this.uid,
    this.role = 'student',
    this.createdAt,
    this.system = false,
  });

  final String id;
  final String? uid;
  final String name;
  final String text;
  final String role;
  final DateTime? createdAt;

  /// True for the room's own announcements — "Ada raised a hand".
  final bool system;

  bool get isHost => role == 'host' || role == 'admin' || role == 'teacher';

  factory LiveMessage.fromMap(String id, Map<String, dynamic> m) {
    final ms = tsToMs(m['createdAt']);
    return LiveMessage(
      id: id,
      uid: m['uid']?.toString(),
      name: (m['name'] ?? 'Student').toString(),
      text: (m['text'] ?? '').toString(),
      role: (m['role'] ?? 'student').toString(),
      createdAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      system: m['system'] == true || m['type'] == 'system',
    );
  }
}
