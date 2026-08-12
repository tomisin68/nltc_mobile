import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/models/chat.dart';
import '../services/api_client.dart';

/// Direct messages and group chats.
///
/// Reads and writes the same `chats` collection the website's ChatView uses, so a
/// conversation started in a browser continues in the app.
///
/// The one shape everything here is built around: **nobody is put into a group
/// by somebody else.** An admin writes a uid into `pendingMembers`, and the only
/// writer the rules will let move it across into `members` is that uid. So the
/// group-administration methods below come in pairs — one for the person doing
/// the inviting, one for the person answering — and there is deliberately no
/// method that adds a member outright, because the server would refuse it.
class ChatRepository {
  ChatRepository({
    required ApiClient api,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _api = api,
        _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final ApiClient _api;
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  /// The ceiling the storage rules enforce on `chat-files/`.
  static const maxAttachmentBytes = 50 * 1024 * 1024;

  CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection('chats');

  DocumentReference<Map<String, dynamic>> _chat(String id) => _chats.doc(id);

  CollectionReference<Map<String, dynamic>> _messages(String chatId) =>
      _chat(chatId).collection('messages');

  // ─── Conversations ────────────────────────────────────────────────────────

  /// Every conversation this student is in, most recent first.
  ///
  /// Sorted client-side rather than with `orderBy`: the composite index on
  /// (`members` array-contains, `lastActivity`) exists on the web project, but a
  /// brand-new conversation has a null `lastActivity` until its first message and
  /// would be dropped from an ordered query.
  Stream<List<Chat>> watchChats(String uid) => _chats
          .where('members', arrayContains: uid)
          .snapshots()
          .map((snap) {
        final chats =
            snap.docs.map((d) => Chat.fromMap(d.id, d.data())).toList();
        chats.sort((a, b) {
          final aTime = a.lastActivity?.millisecondsSinceEpoch ?? 0;
          final bTime = b.lastActivity?.millisecondsSinceEpoch ?? 0;
          return bTime.compareTo(aTime);
        });
        return chats;
      });

  /// Groups this student has been invited to and not yet answered.
  ///
  /// A separate query rather than a widening of [watchChats], because the two
  /// lists mean different things and are shown in different places: these are
  /// decisions waiting to be made, not conversations. The rules let an invited
  /// student read the chat document — the group's name and who invited them,
  /// which is what an invitation has to say — while its messages stay shut
  /// until they accept.
  Stream<List<Chat>> watchGroupInvites(String uid) => _chats
      .where('pendingMembers', arrayContains: uid)
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            if (Chat.fromMap(doc.id, doc.data()) case final chat
                when chat.isGroup && !chat.members.contains(uid))
              chat,
        ],
      );

  Stream<Chat?> watchChat(String chatId) => _chat(chatId).snapshots().map(
        (snap) => snap.exists ? Chat.fromMap(snap.id, snap.data() ?? {}) : null,
      );

  Stream<List<ChatMessage>> watchMessages(String chatId, {int limit = 150}) =>
      _messages(chatId)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => ChatMessage.fromMap(d.id, d.data()))
                .toList()
                .reversed
                .toList(),
          );

  // ─── Sending ──────────────────────────────────────────────────────────────

  /// Posts a message and bumps the conversation in one batch.
  ///
  /// The message and the chat's summary must land together: a message with no
  /// matching `lastActivity` sinks to the bottom of everyone's list, and a
  /// summary with no message reads as a phantom.
  ///
  /// Returns the id the message was written under, which the caller already
  /// showed optimistically.
  ///
  /// [clientId] is the id of that optimistic bubble. It is stored on the message
  /// so the sender's own copy can be matched exactly when it comes back down the
  /// stream — matching on the text instead meant two identical messages retired
  /// each other, and an attachment retired nothing at all.
  Future<String> sendMessage(
    String chatId, {
    required Chat chat,
    required String senderId,
    required String senderName,
    String? senderPhoto,
    required String text,
    QuotedMessage? replyTo,
    String? clientId,
  }) async {
    final body = text.trim();
    if (body.isEmpty) throw ArgumentError('Cannot send an empty message');

    final messageRef = _messages(chatId).doc();
    // A client timestamp on the message rather than a sentinel: the sender has
    // already seen it in place, and a sentinel would make it jump position when
    // the server resolves it.
    final now = Timestamp.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch,
    );

    final batch = _db.batch();
    batch.set(messageRef, {
      'text': body,
      'senderId': senderId,
      'senderName': senderName,
      'senderPhoto': senderPhoto,
      'timestamp': now,
      // Alongside it, and only for the ticks: read and delivery receipts are
      // server-stamped, so a device with a wrong clock would otherwise compare
      // its own idea of "now" against everyone else's and never agree.
      'serverTimestamp': FieldValue.serverTimestamp(),
      'type': 'text',
      'clientId': ?clientId,
      if (replyTo != null) 'replyTo': replyTo.toJson(),
    });

    batch.update(_chat(chatId), {
      'lastMessage': {
        'text': body,
        'senderId': senderId,
        'senderName': senderName,
        'timestamp': FieldValue.serverTimestamp(),
      },
      'lastActivity': FieldValue.serverTimestamp(),
      'typing.$senderId': FieldValue.delete(),
      // Everyone but the sender gains an unread.
      for (final member in chat.members)
        if (member != senderId) 'unreadCount.$member': FieldValue.increment(1),
    });

    await _guarded(batch.commit, _postRefusal(chat));
    unawaited(
      notifyRecipients(
        chatId: chatId,
        chat: chat,
        preview: body,
        senderName: senderName,
      ),
    );
    return messageRef.id;
  }

  /// Why the server turned a message away.
  static String _postRefusal(Chat chat) => chat.locked
      ? 'This group is set to announcements only — only its admins can post.'
      : 'You cannot post in this conversation.';

  /// Clears this student's unread badge and stamps them as caught up.
  ///
  /// `readBy` is what the sender's blue ticks are computed from — without the
  /// stamp their message stays grey forever, so the two are written together.
  /// `deliveredTo` goes with them because reading a message is proof of having
  /// received it, and a chat opened straight from a push notification never
  /// passes through the list that would otherwise have stamped it.
  Future<void> markRead(String chatId, String uid) async {
    try {
      await _chat(chatId).update({
        'unreadCount.$uid': 0,
        'readBy.$uid': FieldValue.serverTimestamp(),
        'deliveredTo.$uid': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Opening a chat must never fail because the badge couldn't be cleared.
    }
  }

  /// Records that everything in this conversation has reached this student's
  /// device — the sender's second tick.
  ///
  /// Deliberately not "they are online": a green dot says where somebody was a
  /// minute ago, whereas this is written by the recipient's own app at the
  /// moment the message lands on it, wherever in the app they happen to be.
  Future<void> markDelivered(String chatId, String uid) async {
    try {
      await _chat(chatId).update({
        'deliveredTo.$uid': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // A receipt is a courtesy to the sender; failing to send one is not
      // something the recipient should ever hear about.
    }
  }

  // ─── Attachments ──────────────────────────────────────────────────────────

  /// Uploads [file] and posts it as a message.
  ///
  /// Everything goes to `chat-files/{chatId}/…` as a `type: 'file'` message with
  /// a `mimeCategory` — including voice notes. The retired `voice-notes/` path is
  /// write-denied by the storage rules, and the website's own renderer keys off
  /// `mimeCategory`, so an audio file posted this way plays there exactly as a
  /// voice note should.
  ///
  /// [onProgress] reports 0..1 as the bytes go up.
  Future<void> sendAttachment(
    String chatId, {
    required Chat chat,
    required File file,
    required String fileName,
    required String mimeType,
    required String senderId,
    required String senderName,
    String? senderPhoto,
    String? caption,
    QuotedMessage? replyTo,
    String? clientId,
    void Function(double progress)? onProgress,
  }) async {
    final size = await file.length();
    if (size > maxAttachmentBytes) {
      throw const ApiException('Files must be under 50 MB.');
    }

    final category = MediaCategory.fromMime(mimeType);
    final extension = fileName.contains('.') ? fileName.split('.').last : 'bin';
    final path =
        'chat-files/$chatId/${DateTime.now().millisecondsSinceEpoch}_$senderId.$extension';

    final task = _storage.ref(path).putFile(
          file,
          SettableMetadata(contentType: mimeType),
        );

    final progressSub = task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        onProgress?.call(snapshot.bytesTransferred / snapshot.totalBytes);
      }
    });

    try {
      await task;
      final url = await _storage.ref(path).getDownloadURL();
      final trimmedCaption = caption?.trim();
      final summary = trimmedCaption?.isNotEmpty ?? false
          ? trimmedCaption!
          : category == MediaCategory.document
              ? '📎 $fileName'
              : category.label;

      final batch = _db.batch();
      batch.set(_messages(chatId).doc(), {
        'type': 'file',
        'fileUrl': url,
        'fileName': fileName,
        'fileType': mimeType,
        'fileSize': size,
        'mimeCategory': category.name,
        'caption': trimmedCaption?.isEmpty ?? true ? null : trimmedCaption,
        // `text` carries the summary so the website's list preview and any older
        // reader that only knows about text still shows something sensible.
        'text': summary,
        'senderId': senderId,
        'senderName': senderName,
        'senderPhoto': senderPhoto,
        // A client timestamp, like a text message: a pending sentinel reads back
        // as null locally, which sorts an attachment straight out of the
        // most-recent window the thread is querying until the server answers.
        'timestamp': Timestamp.fromMillisecondsSinceEpoch(
          DateTime.now().millisecondsSinceEpoch,
        ),
        'serverTimestamp': FieldValue.serverTimestamp(),
        'clientId': ?clientId,
        if (replyTo != null) 'replyTo': replyTo.toJson(),
      });
      batch.update(_chat(chatId), {
        'lastMessage': {
          'text': summary,
          'senderId': senderId,
          'senderName': senderName,
          'timestamp': FieldValue.serverTimestamp(),
        },
        'lastActivity': FieldValue.serverTimestamp(),
        'typing.$senderId': FieldValue.delete(),
        for (final member in chat.members)
          if (member != senderId) 'unreadCount.$member': FieldValue.increment(1),
      });
      await _guarded(batch.commit, _postRefusal(chat));

      unawaited(
        notifyRecipients(
          chatId: chatId,
          chat: chat,
          preview: summary,
          senderName: senderName,
        ),
      );
    } finally {
      await progressSub.cancel();
    }
  }

  /// Asks the backend to push this message to everyone else in the chat.
  ///
  /// Best-effort: the message is already saved and visible by the time this
  /// runs, so a failed push is not worth an error.
  Future<void> notifyRecipients({
    required String chatId,
    required Chat chat,
    required String preview,
    required String senderName,
  }) async {
    try {
      await _api.post('/notifications/chat-message', {
        'chatId': chatId,
        'messageText':
            preview.length > 120 ? '${preview.substring(0, 117)}…' : preview,
        'chatType': chat.isGroup ? 'group' : 'dm',
        'chatName': chat.isGroup ? chat.name : senderName,
        'senderName': senderName,
      });
    } catch (_) {
      // The message stands whether or not the push went out.
    }
  }

  /// Tells [uids] they have been invited to a group.
  ///
  /// Best-effort, like every other push here. It matters more than most,
  /// though: an invitation nobody is told about is one that sits unanswered,
  /// and the whole point of asking is that somebody gets to answer.
  Future<void> _notifyInvitees({
    required String chatId,
    required String groupName,
    required String inviterName,
    required List<String> uids,
  }) async {
    if (uids.isEmpty) return;
    try {
      await _api.post('/notifications/group-invite', {
        'chatId': chatId,
        'uids': uids,
        'groupName': groupName,
        'inviterName': inviterName,
      });
    } catch (_) {
      // The invitation itself is stored either way, and both clients show it
      // in the invitations tray whether or not a push went out.
    }
  }

  Future<void> setTyping(String chatId, String uid, bool typing) async {
    try {
      await _chat(chatId).update({
        'typing.$uid': typing
            ? DateTime.now().millisecondsSinceEpoch
            : FieldValue.delete(),
      });
    } catch (_) {/* cosmetic */}
  }

  /// Soft-deletes a message for everyone. Only the `deleted` flag may change, per
  /// the rules, so the text stays in the document and the UI hides it.
  Future<void> deleteForEveryone(String chatId, String messageId) =>
      _messages(chatId).doc(messageId).update({'deleted': true});

  /// Hides a message for this student only.
  Future<void> deleteForMe(String chatId, String messageId, String uid) =>
      _messages(chatId).doc(messageId).update({
        'deletedFor': FieldValue.arrayUnion([uid]),
      });

  /// Hides several messages at once — what selection mode commits.
  ///
  /// Only ever "delete for me": a bulk delete-for-everyone is not something the
  /// website offers, and it is not a mistake worth making easy.
  Future<void> deleteManyForMe(
    String chatId,
    Iterable<String> messageIds,
    String uid,
  ) async {
    final ids = messageIds.toList();
    if (ids.isEmpty) return;

    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_messages(chatId).doc(id), {
        'deletedFor': FieldValue.arrayUnion([uid]),
      });
    }
    await batch.commit();
  }

  /// Adds or removes this student's reaction. One emoji per person per message:
  /// reacting again with a different emoji replaces the first.
  Future<void> toggleReaction(
    String chatId,
    ChatMessage message, {
    required String uid,
    required String emoji,
  }) async {
    final reactions = <String, List<String>>{
      for (final entry in message.reactions.entries)
        entry.key: [...entry.value.where((u) => u != uid)],
    };

    final alreadyReacted = message.reactions[emoji]?.contains(uid) ?? false;
    if (!alreadyReacted) {
      reactions.putIfAbsent(emoji, () => <String>[]).add(uid);
    }
    reactions.removeWhere((_, uids) => uids.isEmpty);

    await _messages(chatId).doc(message.id).update({'reactions': reactions});
  }

  // ─── Starting a conversation ───────────────────────────────────────────────

  /// Opens the DM with [contact], creating it only if there isn't one already.
  ///
  /// The duplicate check runs against the caller's own chat list rather than a
  /// query: `array-contains` cannot test two members at once, and a student is
  /// already subscribed to every chat they're in.
  Future<String> openDirectMessage({
    required List<Chat> existing,
    required String myUid,
    required String myName,
    String? myPhoto,
    required ChatContact contact,
  }) async {
    final match = existing.firstWhere(
      (c) =>
          c.type == ChatType.dm &&
          c.members.contains(myUid) &&
          c.members.contains(contact.uid),
      orElse: () => const Chat(id: '', type: ChatType.dm, members: []),
    );
    if (match.id.isNotEmpty) return match.id;

    final ref = await _chats.add({
      'type': 'dm',
      'members': [myUid, contact.uid],
      'memberNames': {myUid: myName, contact.uid: contact.name},
      'memberPhotos': {myUid: myPhoto, contact.uid: contact.photo},
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': myUid,
      'lastActivity': FieldValue.serverTimestamp(),
      'unreadCount': <String, int>{},
      // A first approach is a request, not a conversation. It sits in the
      // other student's requests tray until they let it through — see
      // [ChatRequestStatus]. Mirrors the website's `startDM`.
      'requestStatus': ChatRequestStatus.pending.wire,
      'requestedBy': myUid,
      'requestFor': contact.uid,
    });
    return ref.id;
  }

  /// Lets a pending conversation through.
  ///
  /// Only the student the request was addressed to may call this — the rules
  /// reject it from anyone else, so a sender cannot accept on their own behalf.
  Future<void> acceptRequest(String chatId) async {
    await _chat(chatId).update({
      'requestStatus': ChatRequestStatus.accepted.wire,
      'requestRespondedAt': FieldValue.serverTimestamp(),
    });
    // The sender is now somebody this student has spoken to, which is what
    // decides who they can be invited into a group with.
    forgetMessagedContacts();
  }

  /// Reports a conversation to the admins, history and all.
  ///
  /// The snapshot is taken server-side rather than posted from here, for two
  /// reasons this app cannot work around: it can only read messages the rules
  /// let it read, and either party can soft-delete a message the moment they
  /// realise a report has been filed. `POST /api/reports/chat` reads past both
  /// with the Admin SDK and freezes the result somewhere neither member of the
  /// chat can reach.
  Future<void> reportChat({
    required String chatId,
    required String reason,
    String details = '',
  }) =>
      _api.post('/reports/chat', {
        'chatId': chatId,
        'reason': reason,
        if (details.isNotEmpty) 'details': details,
      });

  /// Turns a pending conversation down.
  ///
  /// The document stays, holding the decline: deleting it would let the sender
  /// open a fresh request and arrive in the tray again the same afternoon.
  Future<void> declineRequest(String chatId) => _chat(chatId).update({
        'requestStatus': ChatRequestStatus.declined.wire,
        'requestRespondedAt': FieldValue.serverTimestamp(),
      });

  /// Creates a group and invites [contacts] to it.
  ///
  /// The group starts with its creator alone in it. Everyone else is invited,
  /// and joins when — if — they accept: the rules reject a group created with
  /// anybody else already inside, so this is not a policy the app is being
  /// polite about, it is the only shape the server will store.
  Future<String> createGroup({
    required String name,
    required String myUid,
    required String myName,
    String? myPhoto,
    required List<ChatContact> contacts,
  }) async {
    final title = name.trim();
    if (title.isEmpty) throw ArgumentError('A group needs a name');
    if (contacts.isEmpty) throw ArgumentError('A group needs someone in it');

    final ref = await _chats.add({
      'type': 'group',
      'name': title,
      'description': '',
      'members': [myUid],
      'pendingMembers': [for (final c in contacts) c.uid],
      'invitedBy': {for (final c in contacts) c.uid: myUid},
      // Names and photos cover the invited as well as the joined: the
      // invitation card has to be able to say who is asking, and it is read by
      // somebody who cannot see anything else about this group yet.
      'memberNames': {
        myUid: myName,
        for (final c in contacts) c.uid: c.name,
      },
      'memberPhotos': {
        myUid: myPhoto,
        for (final c in contacts) c.uid: c.photo,
      },
      // Both spellings: `groupAdmin` is the founder, which every version of the
      // website and the rules have always read, and `groupAdmins` is the list
      // that lets a group have more than one at a time.
      'groupAdmin': myUid,
      'groupAdmins': [myUid],
      'locked': false,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': myUid,
      'lastActivity': FieldValue.serverTimestamp(),
      'unreadCount': <String, int>{},
    });

    await _messages(ref.id).add({
      'type': 'system',
      'text': '$myName created the group "$title"',
      'timestamp': FieldValue.serverTimestamp(),
    });
    unawaited(
      _notifyInvitees(
        chatId: ref.id,
        groupName: title,
        inviterName: myName,
        uids: [for (final c in contacts) c.uid],
      ),
    );
    return ref.id;
  }

  // ─── Group invitations ────────────────────────────────────────────────────

  /// Accepts an invitation: joins the group and says so in the thread.
  ///
  /// Two writes, in this order and not the other: the announcement can only be
  /// posted by a member, so joining has to land first.
  Future<void> acceptGroupInvite(
    String chatId, {
    required String uid,
    required String name,
  }) async {
    await _guarded(
      () => _chat(chatId).update({
        'members': FieldValue.arrayUnion([uid]),
        'pendingMembers': FieldValue.arrayRemove([uid]),
      }),
      'That invitation is no longer open.',
    );
    await _announce(chatId, '$name joined the group');
  }

  /// Turns an invitation down.
  ///
  /// Nothing is announced. Declining is not news the group is owed, and a
  /// student who does not want to join should not have to explain it to a room
  /// full of people — the same reasoning as a declined message request.
  Future<void> declineGroupInvite(String chatId, {required String uid}) =>
      _guarded(
        () => _chat(chatId).update({
          'pendingMembers': FieldValue.arrayRemove([uid]),
        }),
        'That invitation is no longer open.',
      );

  /// Takes back an invitation nobody has answered yet. Admins only.
  Future<void> withdrawInvite(
    String chatId, {
    required String uid,
  }) =>
      _guarded(
        () => _chat(chatId).update({
          'pendingMembers': FieldValue.arrayRemove([uid]),
          'invitedBy.$uid': FieldValue.delete(),
        }),
        'Only an admin can withdraw an invitation.',
      );

  // ─── Group administration ─────────────────────────────────────────────────

  /// Runs a chat write, turning a rules rejection into something a student can
  /// read.
  ///
  /// The roster rules are strict on purpose, and a student who trips one is
  /// owed the reason rather than "try again" — trying again cannot fix being
  /// refused. [refusal] is what that particular wall means.
  Future<T> _guarded<T>(Future<T> Function() write, String refusal) async {
    try {
      return await write();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') throw ApiException(refusal);
      rethrow;
    }
  }

  /// Posts one of the chat's own announcements — "Ada invited Chidi".
  ///
  /// Never throws. Every one of these is a courtesy attached to something that
  /// has already been decided, and an announcement-only group refuses posts
  /// from anyone but its admins — including the notice that somebody just
  /// joined or left it. Letting that refusal surface would mean a student
  /// could not leave a locked group at all, which is precisely backwards.
  Future<void> _announce(String chatId, String text) async {
    try {
      await _messages(chatId).add({
        'type': 'system',
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // The thing being announced stands whether or not the notice landed.
    }
  }

  Future<void> saveGroupInfo(
    String chatId, {
    required String name,
    required String description,
  }) =>
      _chat(chatId).update({
        'name': name.trim(),
        'description': description.trim(),
      });

  /// Locks the group so only its admin may post — an announcement group.
  Future<void> setGroupLocked(String chatId, bool locked, String byUid) =>
      _chat(chatId).update({
        'locked': locked,
        'lockedBy': locked ? byUid : FieldValue.delete(),
      });

  /// Replaces the group's picture.
  Future<String> uploadGroupPhoto(String chatId, File file) async {
    final reference = _storage.ref('group-photos/$chatId');
    await reference.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final url = await reference.getDownloadURL();
    await _chat(chatId).update({'groupPhoto': url});
    return url;
  }

  /// Invites people to an existing group, and says so in the thread.
  ///
  /// They do not join here — they are asked. The names and photos are
  /// denormalised onto the chat alongside the invitation because an invited
  /// student can read this document and nothing else, so everything their
  /// invitation needs to name has to already be on it.
  Future<void> inviteMembers(
    String chatId, {
    required Chat chat,
    required List<ChatContact> contacts,
    required String byUid,
    required String byName,
  }) async {
    final fresh = contacts
        .where(
          (c) =>
              !chat.members.contains(c.uid) &&
              !chat.pendingMembers.contains(c.uid),
        )
        .toList();
    if (fresh.isEmpty) return;

    await _guarded(
      () => _chat(chatId).update({
        'pendingMembers':
            FieldValue.arrayUnion([for (final c in fresh) c.uid]),
        for (final contact in fresh) 'invitedBy.${contact.uid}': byUid,
        for (final contact in fresh) 'memberNames.${contact.uid}': contact.name,
        for (final contact in fresh)
          'memberPhotos.${contact.uid}': contact.photo,
      }),
      'Only an admin can invite people to this group.',
    );
    await _announce(
      chatId,
      '$byName invited ${fresh.map((c) => c.name).join(', ')}',
    );
    unawaited(
      _notifyInvitees(
        chatId: chatId,
        groupName: chat.name ?? 'a group',
        inviterName: byName,
        uids: [for (final c in fresh) c.uid],
      ),
    );
  }

  /// Removes someone from the group, and from its admins if they were one.
  ///
  /// The two go together: [Chat.admins] already ignores an admin who is no
  /// longer a member, but leaving the uid behind in the stored list would hand
  /// the role straight back if they were ever added again.
  Future<void> removeMember(
    String chatId, {
    required Chat chat,
    required String uid,
  }) async {
    if (chat.admins.length == 1 && chat.isAdmin(uid)) {
      throw const ApiException(
        'That is the only admin. Make someone else an admin first.',
      );
    }

    final admins = chat.admins.where((a) => a != uid).toList();
    await _guarded(
      () => _chat(chatId).update({
        // `arrayRemove` rather than the filtered list this app is holding: the
        // rules compare the result against the stored roster, and somebody
        // joining between the read and this write would otherwise make the
        // comparison — and the removal — fail.
        'members': FieldValue.arrayRemove([uid]),
        if (chat.isAdmin(uid)) ...{
          'groupAdmins': admins,
          if (chat.groupAdmin == uid) 'groupAdmin': admins.first,
        },
      }),
      'Only an admin can change who is in this group.',
    );
  }

  /// Adds [uid] to the group's admins. A group can have as many as it likes.
  ///
  /// `groupAdmin` — the single field the website and the Firestore rules know
  /// about — is left pointing at whoever holds it, so nothing outside the app
  /// loses track of who is in charge. Everything in the app reads [Chat.admins],
  /// which is the union of the two.
  Future<void> addAdmin(
    String chatId, {
    required Chat chat,
    required String uid,
  }) async {
    if (chat.isAdmin(uid)) return;

    // Written as the whole list rather than an `arrayUnion`, because a group
    // made before this field existed has nothing in it and the founder's claim
    // rests on the legacy field alone — [Chat.admins] already folds the two
    // together, so writing it back is what makes them agree.
    await _chat(chatId).update({
      'groupAdmins': [...chat.admins, uid],
      'groupAdmin': chat.groupAdmin ?? chat.admins.firstOrNull ?? uid,
    });
    await _announce(
      chatId,
      '${chat.memberNames[uid] ?? 'Someone'} is now a group admin',
    );
  }

  /// Takes the admin role back off [uid].
  ///
  /// A group is never left with nobody in charge: the last admin cannot be
  /// dismissed, and dismissing whoever currently holds the legacy `groupAdmin`
  /// field hands it to one of the others.
  Future<void> removeAdmin(
    String chatId, {
    required Chat chat,
    required String uid,
  }) async {
    final remaining = chat.admins.where((a) => a != uid).toList();
    if (remaining.isEmpty) {
      throw const ApiException(
        'A group needs at least one admin. Make someone else an admin first.',
      );
    }

    await _chat(chatId).update({
      'groupAdmins': remaining,
      if (chat.groupAdmin == uid) 'groupAdmin': remaining.first,
    });
    await _announce(
      chatId,
      '${chat.memberNames[uid] ?? 'Someone'} is no longer a group admin',
    );
  }

  /// Leaves a group, announcing it on the way out.
  ///
  /// The announcement is posted first: once the member list no longer contains
  /// this student, the rules stop them writing to the thread at all.
  ///
  /// An admin walking out hands the role on rather than taking it with them — a
  /// group whose only admin left could otherwise never be renamed or unlocked
  /// again by anybody.
  Future<void> leaveGroup(
    String chatId, {
    required Chat chat,
    required String uid,
    required String name,
  }) async {
    await _announce(chatId, '$name left the group');

    final members = chat.members.where((m) => m != uid).toList();
    final admins = chat.admins.where((a) => a != uid).toList();
    final successor = admins.isNotEmpty
        ? admins.first
        : members.isNotEmpty
            ? members.first
            : null;

    await _guarded(
      () => _chat(chatId).update({
        // See [removeMember]: the rules check the resulting list, so the
        // server has to do the removing.
        'members': FieldValue.arrayRemove([uid]),
        if (chat.isAdmin(uid)) ...{
          'groupAdmins': admins.isNotEmpty ? admins : [?successor],
          'groupAdmin': ?successor,
        },
      }),
      'Only an admin can change who is in this group.',
    );
  }

  // ─── Finding people ───────────────────────────────────────────────────────

  /// How much of the user collection is held for browsing and local search.
  ///
  /// The website loads every student in one go; a phone should not, so this is a
  /// ceiling rather than a promise. When the collection turns out to be bigger
  /// than this, [searchContacts] stops relying on the cache alone and asks the
  /// server as well — which is the whole reason the cap is safe.
  static const _directoryLimit = 500;

  /// A code point that sorts after anything a name or address can contain, so
  /// `startAt(prefix) … endAt(prefix + this)` is the range of every value
  /// beginning with `prefix`. Spelled as an escape because the character itself
  /// is invisible in an editor and would look like a typo to the next reader.
  static const _prefixCeiling = '\uf8ff';

  List<ChatContact>? _directory;

  /// True when [_directory] is the entire user collection, so a name missing from
  /// it is genuinely not there.
  bool _directoryComplete = false;

  /// People this student can message: their tutors, and other students.
  ///
  /// Held for the life of the app once loaded. The picker is opened and closed
  /// repeatedly — starting one conversation, then a group, then adding someone to
  /// it — and re-reading the collection each time is a round trip a student on a
  /// Nigerian mobile connection feels every single time.
  Future<List<ChatContact>> contacts({bool refresh = false}) async {
    final cached = _directory;
    if (cached != null && !refresh) return cached;

    final snap = await _db.collection('users').limit(_directoryLimit + 1).get();
    _directoryComplete = snap.docs.length <= _directoryLimit;
    final contacts = snap.docs
        .take(_directoryLimit)
        .map((d) => ChatContact.fromMap(d.id, d.data()))
        .toList()
      ..sort(ChatContact.compare);

    _directory = contacts;
    return contacts;
  }

  /// How many document ids one `whereIn` query will take.
  static const _idBatch = 30;

  List<ChatContact>? _messaged;

  /// The people this student may put in a group: everyone they have an open
  /// direct message with.
  ///
  /// Not the directory. A group invitation reaches somebody who never asked for
  /// it, and in August 2026 that was being used to pull whole classes into
  /// groups they had nothing to do with. Requiring a conversation first means
  /// the person doing the inviting has already been let through once, by the
  /// person being invited — a DM request they accepted. Declining a request
  /// therefore closes the group route too, which is the reading of "no" that
  /// anyone declining would expect.
  ///
  /// A pending request does not count. That is somebody who has been asked and
  /// has not said yes.
  ///
  /// Read straight from the chat collection rather than from a cached contact
  /// list, because it has to be *this student's* conversations and nothing
  /// else; the result is held for the session, since a picker is opened and
  /// closed repeatedly while building one group.
  Future<List<ChatContact>> messagedContacts(
    String myUid, {
    bool refresh = false,
  }) async {
    final cached = _messaged;
    if (cached != null && !refresh) return cached;

    final snap = await _chats.where('members', arrayContains: myUid).get();
    final uids = <String>{
      for (final doc in snap.docs)
        if (Chat.fromMap(doc.id, doc.data()) case final chat
            when !chat.isGroup &&
                chat.requestStatus == ChatRequestStatus.accepted)
          ...chat.othersThan(myUid),
    }..remove(myUid);

    final contacts = await _usersByUid(uids);
    contacts.sort(ChatContact.compare);
    _messaged = contacts;
    return contacts;
  }

  /// [messagedContacts] narrowed to whoever answers to [query].
  ///
  /// Filtered here rather than on the server: the list is one student's
  /// conversations, which is small, and the point of the search box in a
  /// contacts-only picker is to find someone in a list they can already see.
  Future<List<ChatContact>> searchMessagedContacts(
    String myUid,
    String query,
  ) async {
    final contacts = await messagedContacts(myUid);
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return contacts;
    return [
      for (final contact in contacts)
        if (contact.matches(needle)) contact,
    ];
  }

  /// Drops the cached contact list, so the next picker sees a conversation
  /// accepted since the app started.
  void forgetMessagedContacts() => _messaged = null;

  /// Reads exactly these people's user documents.
  ///
  /// `whereIn` takes thirty ids at a time, so this runs in chunks; a student's
  /// contact list is small enough that it is nearly always one query.
  Future<List<ChatContact>> _usersByUid(Set<String> uids) async {
    if (uids.isEmpty) return [];

    final ids = uids.toList();
    final chunks = <List<String>>[
      for (var i = 0; i < ids.length; i += _idBatch)
        ids.sublist(i, i + _idBatch > ids.length ? ids.length : i + _idBatch),
    ];

    final snapshots = await Future.wait(
      chunks.map(
        (chunk) => _db
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      ),
    );

    return [
      for (final snap in snapshots)
        for (final doc in snap.docs) ChatContact.fromMap(doc.id, doc.data()),
    ];
  }

  /// One person's card, kept live for as long as anyone is looking at it.
  ///
  /// A document listener rather than a one-off read because this is what the
  /// profile a student taps through to is drawn from, and their name, photo and
  /// presence are all on the same document — a snapshot would show a green dot
  /// that never went out.
  Stream<ChatContact?> watchContact(String uid) =>
      _db.collection('users').doc(uid).snapshots().map(
            (snap) => snap.exists
                ? ChatContact.fromMap(snap.id, snap.data() ?? const {})
                : null,
          );

  /// Everyone matching [query], by name or email.
  ///
  /// Firestore has no substring search, so this is two passes: the cached
  /// directory filtered locally, which is instant and matches anywhere in the
  /// name, plus — only when the directory was capped — prefix queries against the
  /// server so that someone outside the cached slice can still be found. Without
  /// the second pass a student whose account happens to sort past the cap is
  /// simply unreachable, which is exactly how a search box comes to look broken.
  Future<List<ChatContact>> searchContacts(String query) async {
    final needle = query.trim().toLowerCase();
    final directory = await contacts();
    if (needle.isEmpty) return directory;

    final results = <String, ChatContact>{
      for (final contact in directory)
        if (contact.matches(needle)) contact.uid: contact,
    };

    if (!_directoryComplete) {
      for (final found in await _remoteMatches(needle)) {
        results.putIfAbsent(found.uid, () => found);
      }
    }

    return results.values.toList()..sort(ChatContact.compare);
  }

  /// Server-side prefix matches on the fields a person is known by.
  ///
  /// Case matters to Firestore's ordering and not to anyone typing, so each field
  /// is tried both as typed and capitalised — "chi" and "Chi" are different range
  /// starts, and names are stored capitalised while emails are not. Every query is
  /// allowed to fail on its own: a field that no document carries yields nothing
  /// rather than sinking the search.
  Future<List<ChatContact>> _remoteMatches(String needle) async {
    final capitalised = needle[0].toUpperCase() + needle.substring(1);
    final attempts = <({String field, String prefix})>[
      for (final field in ['firstName', 'lastName', 'displayName'])
        for (final prefix in {needle, capitalised}) (field: field, prefix: prefix),
      (field: 'email', prefix: needle),
    ];

    final snapshots = await Future.wait(
      attempts.map(
        (attempt) => _db
            .collection('users')
            .orderBy(attempt.field)
            .startAt([attempt.prefix])
            // The last code point Firestore will order before the next prefix —
            // the standard way to say "starts with" against a range query.
            .endAt(['${attempt.prefix}$_prefixCeiling'])
            .limit(20)
            .get()
            .then<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              (snap) => snap.docs,
            )
            .catchError(
              (_) => <QueryDocumentSnapshot<Map<String, dynamic>>>[],
            ),
      ),
    );

    return [
      for (final docs in snapshots)
        for (final doc in docs) ChatContact.fromMap(doc.id, doc.data()),
    ];
  }
}
