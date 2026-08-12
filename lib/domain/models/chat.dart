import 'app_user.dart' show tsToMs;
import 'user_presence.dart';

/// A one-to-one conversation or a group.
enum ChatType {
  dm,
  group;

  static ChatType parse(String? raw) =>
      raw == 'group' ? ChatType.group : ChatType.dm;
}

/// Whether the person on the receiving end of a new DM has let it through.
///
/// A student can be messaged by anyone else on the platform, which is fine
/// until it isn't — the point of a request is that an unwanted first message
/// arrives in a tray the student chooses to open, not in the conversation list
/// beside their study group, and that declining costs one tap and no
/// explanation.
///
/// Groups answer the same question with [Chat.pendingMembers] instead, because
/// a group is not one conversation with one person to ask.
enum ChatRequestStatus {
  /// Waiting on [Chat.requestFor]. Only they can move it.
  pending,

  /// Either accepted, or a conversation that predates requests entirely —
  /// which is why this, not [pending], is what a missing field means.
  accepted,

  /// Turned down. Stays on the document rather than being deleted so the
  /// sender cannot simply open a fresh one and try again.
  declined;

  static ChatRequestStatus parse(String? raw) => switch (raw) {
        'pending' => ChatRequestStatus.pending,
        'declined' => ChatRequestStatus.declined,
        _ => ChatRequestStatus.accepted,
      };

  String get wire => name;
}

/// How far a message this student sent has got.
///
/// Four states rather than the web's two, because "it left my phone" and "it
/// reached theirs" are different pieces of news and a student waiting on an
/// answer reads the difference. [delivered] is a real receipt — the recipient's
/// app wrote it after receiving the message — not a guess made from whether
/// they happen to look online.
enum MessageStatus {
  /// Still being written. Drawn as a clock.
  sending,

  /// On the server. Nobody has received it yet.
  sent,

  /// Every other member's device has it.
  delivered,

  /// Every other member has opened the conversation since it arrived.
  read,
}

/// A conversation, as `chats/{chatId}` describes it.
///
/// Member names and photos are denormalised onto the chat document because that
/// is how the website writes it: listing conversations would otherwise cost one
/// user read per row, every time the list rebuilds.
class Chat {
  const Chat({
    required this.id,
    required this.type,
    required this.members,
    this.pendingMembers = const [],
    this.invitedBy = const {},
    this.name,
    this.description,
    this.memberNames = const {},
    this.memberPhotos = const {},
    this.groupAdmin,
    this.groupAdmins = const [],
    this.groupPhoto,
    this.locked = false,
    this.lastMessage,
    this.lastActivity,
    this.unreadCount = const {},
    this.typing = const {},
    this.readBy = const {},
    this.deliveredTo = const {},
    this.requestStatus = ChatRequestStatus.accepted,
    this.requestedBy,
    this.requestFor,
  });

  final String id;
  final ChatType type;

  /// Firebase uids of everyone actually in the conversation.
  ///
  /// For a group this only ever grows by somebody accepting an invitation:
  /// the rules let an admin write [pendingMembers], and let nobody but the
  /// invited student move their own uid across into here.
  final List<String> members;

  /// Firebase uids who have been invited to a group and have not answered yet.
  ///
  /// They can read this document — they have to see what they are being asked
  /// to join — and nothing else: the messages are shut to them until they are
  /// in [members]. Always empty for a DM, where [requestStatus] asks the same
  /// question of the one person it concerns.
  final List<String> pendingMembers;

  /// uid of an invited student → uid of whoever invited them.
  ///
  /// What lets the invitation say "Ada added you" rather than "you have been
  /// added", which is the difference between a person asking and a system
  /// announcing.
  final Map<String, String> invitedBy;

  /// The group's name. Null for a DM, which is titled after the other person.
  final String? name;
  final String? description;

  final Map<String, String> memberNames;
  final Map<String, String?> memberPhotos;

  /// The member who created the group.
  ///
  /// Kept as its own field, and always one of [admins], because it is the only
  /// one the website and the Firestore rules know about: `canPostMessage()`
  /// compares against this exact field when a group is locked. Everything in the
  /// app reads [admins] instead, so a group can have several.
  final String? groupAdmin;

  /// Everyone who may rename the group, manage its members, lock it, and
  /// appoint other admins.
  ///
  /// Read through [admins] rather than directly — a group created before this
  /// existed has an empty list and only [groupAdmin] to go on.
  final List<String> groupAdmins;

  final String? groupPhoto;

  /// True when only an admin may post — an announcement group.
  final bool locked;

  final ChatPreview? lastMessage;
  final DateTime? lastActivity;

  /// uid → how many messages that person hasn't read.
  final Map<String, int> unreadCount;

  /// uid → the millisecond timestamp they last typed.
  final Map<String, int> typing;

  /// uid → when that person last had the conversation open, in millis.
  ///
  /// What the read ticks are computed from: a message is read by someone if
  /// their `readBy` stamp is at or after the message's own.
  final Map<String, int> readBy;

  /// uid → when that person's device last received everything in this chat.
  ///
  /// Written by the recipient, not guessed by the sender: their app stamps it
  /// the moment a message reaches them, wherever in the app they happen to be.
  /// That is what separates the grey double tick from the single one.
  final Map<String, int> deliveredTo;

  /// Where this DM stands with the person who was messaged.
  final ChatRequestStatus requestStatus;

  /// Who opened the conversation. Their side is never held up.
  final String? requestedBy;

  /// Who has to accept. The only member allowed to change [requestStatus] —
  /// the Firestore rules enforce that, not just this app.
  final String? requestFor;

  bool get isGroup => type == ChatType.group;

  /// True when [uid] is the one being asked, and hasn't answered yet.
  ///
  /// This is what keeps the conversation out of the main list and in the
  /// requests tray.
  bool isPendingFor(String? uid) =>
      requestStatus == ChatRequestStatus.pending &&
      uid != null &&
      requestFor == uid;

  /// True when [uid] has been invited to this group and hasn't answered.
  ///
  /// The whole group is held out of their conversation list while this is
  /// true — they can see the invitation and nothing else.
  bool isInvitePendingFor(String? uid) =>
      uid != null && pendingMembers.contains(uid);

  /// Whoever invited [uid], as a name to put in the invitation.
  String? inviterNameFor(String uid) {
    final inviter = invitedBy[uid];
    return inviter == null ? null : memberNames[inviter];
  }

  /// Everyone waiting on an invitation, with the ones who can be named first —
  /// a settings list wants to show people, not uids.
  List<String> get invitees => [
        for (final uid in pendingMembers)
          if (!members.contains(uid)) uid,
      ];

  /// True when [uid] sent the request and is still waiting.
  bool isAwaitingReplyFrom(String? uid) =>
      requestStatus == ChatRequestStatus.pending &&
      uid != null &&
      requestFor != uid;

  /// True when nobody should be able to type into this conversation any more.
  bool get isDeclined => requestStatus == ChatRequestStatus.declined;

  int unreadFor(String? uid) => uid == null ? 0 : (unreadCount[uid] ?? 0);

  /// Everyone but [myUid].
  List<String> othersThan(String myUid) =>
      members.where((m) => m != myUid).toList();

  /// How far [message] has got, from the point of view of whoever sent it.
  ///
  /// "Everyone else" rather than "somebody": in a group, two ticks mean the
  /// whole group has it, which is the only reading that stays true as people
  /// are added.
  MessageStatus statusOf(ChatMessage message, String myUid) {
    if (message.pending) return MessageStatus.sending;

    final at = message.receiptTime;
    final others = othersThan(myUid);
    if (at == null || others.isEmpty) return MessageStatus.sent;

    final ms = at.millisecondsSinceEpoch;
    if (others.every((uid) => (readBy[uid] ?? 0) >= ms)) {
      return MessageStatus.read;
    }
    if (others.every((uid) => _receiptFor(uid) >= ms)) {
      return MessageStatus.delivered;
    }
    return MessageStatus.sent;
  }

  /// The later of someone's delivery and read stamps.
  ///
  /// Having read a message is proof of having received it, and the two are
  /// written by different code paths — a chat opened straight from a push
  /// notification stamps `readBy` without ever passing through the list that
  /// stamps `deliveredTo`.
  int _receiptFor(String uid) {
    final delivered = deliveredTo[uid] ?? 0;
    final read = readBy[uid] ?? 0;
    return delivered > read ? delivered : read;
  }

  bool get isLockedForMembers => locked;

  /// Everyone who can administer this group, oldest claim first.
  ///
  /// Folds the legacy single-admin field in, and drops anyone who has since
  /// left, so a group whose only admin walked out doesn't leave a ghost in the
  /// list.
  List<String> get admins => [
        if (groupAdmin != null && members.contains(groupAdmin)) groupAdmin!,
        for (final uid in groupAdmins)
          if (uid != groupAdmin && members.contains(uid)) uid,
      ];

  bool isAdmin(String? uid) => uid != null && admins.contains(uid);

  /// The other person in a DM.
  String? otherMember(String myUid) =>
      members.where((m) => m != myUid).firstOrNull;

  /// What to put in the list row and the conversation header.
  String titleFor(String myUid) {
    if (isGroup) return name ?? 'Group';
    final other = otherMember(myUid);
    return (other == null ? null : memberNames[other]) ?? 'Student';
  }

  String? avatarFor(String myUid) {
    if (isGroup) return groupPhoto;
    final other = otherMember(myUid);
    return other == null ? null : memberPhotos[other];
  }

  /// Whoever is typing right now, other than [myUid].
  ///
  /// The website leaves a stale marker behind whenever a tab is closed
  /// mid-sentence, so anything older than the timeout is ignored rather than
  /// shown as a permanent "typing…".
  List<String> typistsOtherThan(String myUid) {
    final cutoff = DateTime.now().millisecondsSinceEpoch - typingTimeoutMs;
    return [
      for (final entry in typing.entries)
        if (entry.key != myUid && entry.value > cutoff)
          memberNames[entry.key] ?? 'Someone',
    ];
  }

  static const typingTimeoutMs = 6000;

  bool canPost(String? uid) => !locked || isAdmin(uid);

  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  factory Chat.fromMap(String id, Map<String, dynamic> m) {
    final names = <String, String>{};
    if (m['memberNames'] is Map) {
      (m['memberNames'] as Map).forEach(
        (key, value) => names[key.toString()] = value?.toString() ?? 'Student',
      );
    }

    final photos = <String, String?>{};
    if (m['memberPhotos'] is Map) {
      (m['memberPhotos'] as Map).forEach(
        (key, value) => photos[key.toString()] = _str(value),
      );
    }

    final unread = <String, int>{};
    if (m['unreadCount'] is Map) {
      (m['unreadCount'] as Map).forEach((key, value) {
        if (value is num) unread[key.toString()] = value.toInt();
      });
    }

    final typing = <String, int>{};
    if (m['typing'] is Map) {
      (m['typing'] as Map).forEach((key, value) {
        final ms = tsToMs(value);
        if (ms != null) typing[key.toString()] = ms;
      });
    }

    final readBy = <String, int>{};
    if (m['readBy'] is Map) {
      (m['readBy'] as Map).forEach((key, value) {
        final ms = tsToMs(value);
        if (ms != null) readBy[key.toString()] = ms;
      });
    }

    final deliveredTo = <String, int>{};
    if (m['deliveredTo'] is Map) {
      (m['deliveredTo'] as Map).forEach((key, value) {
        final ms = tsToMs(value);
        if (ms != null) deliveredTo[key.toString()] = ms;
      });
    }

    final invitedBy = <String, String>{};
    if (m['invitedBy'] is Map) {
      (m['invitedBy'] as Map).forEach((key, value) {
        final inviter = _str(value);
        if (inviter != null) invitedBy[key.toString()] = inviter;
      });
    }

    final activity = tsToMs(m['lastActivity']);

    return Chat(
      id: id,
      type: ChatType.parse(_str(m['type'])),
      members: m['members'] is List
          ? (m['members'] as List).map((e) => e.toString()).toList()
          : const [],
      // Absent on every DM and on every group made before invitations existed,
      // which reads correctly as "nobody is waiting".
      pendingMembers: m['pendingMembers'] is List
          ? [
              for (final uid in m['pendingMembers'] as List)
                if (_str(uid) != null) uid.toString().trim(),
            ]
          : const [],
      invitedBy: invitedBy,
      name: _str(m['name']),
      description: _str(m['description']),
      memberNames: names,
      memberPhotos: photos,
      groupAdmin: _str(m['groupAdmin']),
      groupAdmins: m['groupAdmins'] is List
          ? [
              for (final uid in m['groupAdmins'] as List)
                if (_str(uid) != null) uid.toString().trim(),
            ]
          : const [],
      groupPhoto: _str(m['groupPhoto']),
      locked: m['locked'] == true,
      lastMessage: ChatPreview.parse(m['lastMessage']),
      lastActivity:
          activity == null ? null : DateTime.fromMillisecondsSinceEpoch(activity),
      unreadCount: unread,
      typing: typing,
      readBy: readBy,
      deliveredTo: deliveredTo,
      // A chat written before requests existed has none of these three, and
      // `parse` reads a missing status as accepted — so old conversations
      // stay exactly where they were rather than all landing in the tray.
      requestStatus: ChatRequestStatus.parse(_str(m['requestStatus'])),
      requestedBy: _str(m['requestedBy']),
      requestFor: _str(m['requestFor']),
    );
  }
}

/// The one-line summary shown in the conversation list.
class ChatPreview {
  const ChatPreview({required this.text, this.senderId, this.senderName});

  final String text;
  final String? senderId;
  final String? senderName;

  static ChatPreview? parse(dynamic value) {
    if (value is! Map) return null;
    return ChatPreview(
      text: (value['text'] ?? '').toString(),
      senderId: value['senderId']?.toString(),
      senderName: value['senderName']?.toString(),
    );
  }
}

/// What kind of thing a message carries.
///
/// `file` is the shape everything uploaded uses today — the category is carried
/// separately in `mimeCategory`, which is what decides whether it renders as a
/// picture, a player or a download. `audio` is the retired standalone voice-note
/// type; old ones are still in the collection and still have to play.
enum MessageKind {
  text,
  audio,
  file,

  /// The chat's own announcements — "Ada created the group".
  system;

  static MessageKind parse(String? raw) => switch (raw) {
        'audio' => MessageKind.audio,
        'file' => MessageKind.file,
        'system' => MessageKind.system,
        _ => MessageKind.text,
      };
}

/// What an attachment actually is, once its MIME type is read.
enum MediaCategory {
  image,
  video,
  audio,
  document;

  static MediaCategory fromMime(String? mimeType) {
    final mime = (mimeType ?? '').toLowerCase();
    if (mime.startsWith('image/')) return MediaCategory.image;
    if (mime.startsWith('video/')) return MediaCategory.video;
    if (mime.startsWith('audio/')) return MediaCategory.audio;
    return MediaCategory.document;
  }

  static MediaCategory parse(String? raw, {String? mimeType}) =>
      switch (raw) {
        'image' => MediaCategory.image,
        'video' => MediaCategory.video,
        'audio' => MediaCategory.audio,
        'document' => MediaCategory.document,
        _ => MediaCategory.fromMime(mimeType),
      };

  /// The summary shown in the conversation list and the push notification.
  String get label => switch (this) {
        MediaCategory.image => '📷 Photo',
        MediaCategory.video => '🎥 Video',
        MediaCategory.audio => '🎤 Voice note',
        MediaCategory.document => '📎 File',
      };
}

/// One message in a conversation.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.kind,
    required this.text,
    this.senderId,
    this.senderName,
    this.senderPhoto,
    this.sentAt,
    this.serverSentAt,
    this.clientId,
    this.deleted = false,
    this.deletedFor = const [],
    this.reactions = const {},
    this.replyTo,
    this.mediaUrl,
    this.fileName,
    this.fileType,
    this.fileSize,
    this.category,
    this.caption,
    this.pending = false,
    this.uploadProgress,
  });

  final String id;
  final MessageKind kind;
  final String text;
  final String? senderId;
  final String? senderName;
  final String? senderPhoto;

  /// When the sender's own clock says this was written. What the thread is
  /// ordered and dated by, because it is known the instant the bubble appears.
  final DateTime? sentAt;

  /// When the server says it was written.
  ///
  /// Resolves a beat after [sentAt] and only exists on messages this app sent.
  /// Read receipts are server-stamped, so comparing them against [sentAt] made
  /// the ticks a function of how far wrong the sender's clock was — a phone set
  /// ten minutes fast never saw a message go blue. See [receiptTime].
  final DateTime? serverSentAt;

  /// The id the sender's own optimistic bubble was given, echoed back on the
  /// stored message so it can be matched and retired exactly rather than by
  /// guessing from its text.
  final String? clientId;

  /// Soft-deleted for everyone.
  final bool deleted;

  /// uids who deleted it only for themselves.
  final List<String> deletedFor;

  /// Emoji → the uids who reacted with it.
  final Map<String, List<String>> reactions;

  final QuotedMessage? replyTo;

  /// Where the attachment lives. Null for a plain text message.
  final String? mediaUrl;
  final String? fileName;
  final String? fileType;

  /// Bytes.
  final int? fileSize;

  final MediaCategory? category;

  /// The text typed alongside a photo or file.
  final String? caption;

  /// True for a message shown optimistically, before the write lands. Drawn with
  /// a clock rather than a tick so a student on a slow connection can see the
  /// difference between "sending" and "sent".
  final bool pending;

  /// 0..1 while an attachment is uploading. Null once it has landed.
  final double? uploadProgress;

  bool get isSystem => kind == MessageKind.system;

  /// The timestamp read receipts are measured against — server time wherever
  /// there is any, falling back to the sender's clock for messages written
  /// before this field existed and for anything the website posts.
  DateTime? get receiptTime => serverSentAt ?? sentAt;

  bool get hasAttachment =>
      !deleted && mediaUrl != null && mediaUrl!.isNotEmpty;

  /// What kind of attachment this is, falling back to the MIME type and then to
  /// the retired standalone voice-note type.
  MediaCategory get mediaCategory =>
      category ??
      (kind == MessageKind.audio
          ? MediaCategory.audio
          : MediaCategory.fromMime(fileType));

  bool isVisibleTo(String uid) => !deletedFor.contains(uid);

  /// A human file size — "1.4 MB".
  String? get readableSize {
    final bytes = fileSize;
    if (bytes == null || bytes <= 0) return null;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// What to show in place of the text for a media message.
  String get displayText {
    if (deleted) return 'This message was deleted';
    if (caption != null && caption!.isNotEmpty) return caption!;
    if (text.isNotEmpty) return text;
    if (hasAttachment) {
      return mediaCategory == MediaCategory.document
          ? '📎 ${fileName ?? 'File'}'
          : mediaCategory.label;
    }
    return '';
  }

  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  factory ChatMessage.fromMap(String id, Map<String, dynamic> m) {
    final reactions = <String, List<String>>{};
    if (m['reactions'] is Map) {
      (m['reactions'] as Map).forEach((emoji, uids) {
        if (uids is List) {
          reactions[emoji.toString()] =
              uids.map((u) => u.toString()).toList(growable: false);
        }
      });
    }

    final ms = tsToMs(m['timestamp']);
    final serverMs = tsToMs(m['serverTimestamp']);

    return ChatMessage(
      id: id,
      kind: MessageKind.parse(_str(m['type'])),
      text: (m['text'] ?? '').toString(),
      senderId: _str(m['senderId']),
      senderName: _str(m['senderName']),
      senderPhoto: _str(m['senderPhoto']),
      sentAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      serverSentAt: serverMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(serverMs),
      clientId: _str(m['clientId']),
      deleted: m['deleted'] == true,
      deletedFor: m['deletedFor'] is List
          ? (m['deletedFor'] as List).map((e) => e.toString()).toList()
          : const [],
      reactions: reactions,
      replyTo: QuotedMessage.parse(m['replyTo']),
      // `audioUrl` is the retired voice-note field; `fileUrl` is what every
      // attachment written since uses.
      mediaUrl: _str(m['fileUrl']) ??
          _str(m['audioUrl']) ??
          _str(m['url']) ??
          _str(m['mediaUrl']),
      fileName: _str(m['fileName']) ?? _str(m['name']),
      fileType: _str(m['fileType']),
      fileSize: m['fileSize'] is num ? (m['fileSize'] as num).toInt() : null,
      category: m['mimeCategory'] == null && m['fileType'] == null
          ? null
          : MediaCategory.parse(
              _str(m['mimeCategory']),
              mimeType: _str(m['fileType']),
            ),
      caption: _str(m['caption']),
    );
  }

  /// A copy with the upload's progress moved on, for the optimistic bubble.
  ChatMessage withProgress(double progress) => ChatMessage(
        id: id,
        kind: kind,
        text: text,
        senderId: senderId,
        senderName: senderName,
        senderPhoto: senderPhoto,
        sentAt: sentAt,
        serverSentAt: serverSentAt,
        clientId: clientId,
        deleted: deleted,
        deletedFor: deletedFor,
        reactions: reactions,
        replyTo: replyTo,
        mediaUrl: mediaUrl,
        fileName: fileName,
        fileType: fileType,
        fileSize: fileSize,
        category: category,
        caption: caption,
        pending: pending,
        uploadProgress: progress,
      );
}

/// The snippet quoted above a reply.
class QuotedMessage {
  const QuotedMessage({
    required this.messageId,
    required this.text,
    this.senderName,
  });

  final String messageId;
  final String text;
  final String? senderName;

  Map<String, dynamic> toJson() => {
        'msgId': messageId,
        'text': text,
        'senderName': senderName,
      };

  static QuotedMessage? parse(dynamic value) {
    if (value is! Map) return null;
    final id = value['msgId']?.toString();
    if (id == null || id.isEmpty) return null;
    return QuotedMessage(
      messageId: id,
      text: (value['text'] ?? '').toString(),
      senderName: value['senderName']?.toString(),
    );
  }
}

/// Someone a student can start a conversation with.
class ChatContact {
  const ChatContact({
    required this.uid,
    required this.name,
    this.email,
    this.photo,
    this.role = 'student',
    this.presence = UserPresence.unknown,
  });

  final String uid;
  final String name;

  /// Searchable alongside the name, because a student looking for a classmate
  /// they only know from a group often knows the address and not the spelling —
  /// the website's picker matches on it too.
  final String? email;

  final String? photo;
  final String role;

  /// How they looked when the directory was read.
  ///
  /// A snapshot rather than a live feed on purpose: the picker can list hundreds
  /// of people, and a document listener each would be hundreds of listeners for a
  /// green dot. It still reads `lastSeen` as well as the flag, so someone whose
  /// browser was force-quit — leaving `online: true` behind forever — is not
  /// shown as sitting there waiting.
  final UserPresence presence;

  bool get isTutor => role == 'admin' || role == 'teacher';

  /// Whether this person answers to [query], which is already lower-cased.
  bool matches(String query) =>
      name.toLowerCase().contains(query) ||
      (email?.toLowerCase().contains(query) ?? false);

  /// Tutors first, then alphabetically — the person a student most often wants
  /// is the one teaching them.
  static int compare(ChatContact a, ChatContact b) {
    if (a.isTutor != b.isTutor) return a.isTutor ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  factory ChatContact.fromMap(String uid, Map<String, dynamic> m) {
    final first = (m['firstName'] ?? '').toString().trim();
    final last = (m['lastName'] ?? '').toString().trim();
    final full = [first, last].where((p) => p.isNotEmpty).join(' ');
    final email = (m['email'] ?? '').toString().trim();

    return ChatContact(
      uid: uid,
      name: full.isNotEmpty
          ? full
          : ((m['displayName'] ?? '').toString().trim().isNotEmpty
              ? m['displayName'].toString().trim()
              : (email.isNotEmpty ? email : 'Student')),
      email: email.isEmpty ? null : email,
      photo: (m['profileImage'] ?? m['photoURL'])?.toString(),
      role: (m['role'] ?? 'student').toString(),
      presence: UserPresence.fromMap(m),
    );
  }
}
