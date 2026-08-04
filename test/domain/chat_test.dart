import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/chat.dart';

/// The ticks and the admin list are the two things about a conversation that a
/// student reads as a statement of fact — "they have it" and "they can do that"
/// — so both are pinned here rather than left to the screens that draw them.
void main() {
  const me = 'me';
  const them = 'them';
  const third = 'third';

  final sentAt = DateTime(2026, 8, 3, 10, 0);
  final ms = sentAt.millisecondsSinceEpoch;

  ChatMessage message({
    String id = 'm1',
    bool pending = false,
    DateTime? at,
    DateTime? serverAt,
    String sender = me,
  }) =>
      ChatMessage(
        id: id,
        kind: MessageKind.text,
        text: 'hello',
        senderId: sender,
        sentAt: at ?? sentAt,
        serverSentAt: serverAt,
        pending: pending,
      );

  Chat dm({
    Map<String, int> readBy = const {},
    Map<String, int> deliveredTo = const {},
  }) =>
      Chat(
        id: 'c1',
        type: ChatType.dm,
        members: const [me, them],
        readBy: readBy,
        deliveredTo: deliveredTo,
      );

  group('Chat.statusOf', () {
    test('a message still being written shows as sending', () {
      expect(
        dm().statusOf(message(pending: true), me),
        MessageStatus.sending,
      );
    });

    test('nobody has it yet — one tick', () {
      expect(dm().statusOf(message(), me), MessageStatus.sent);
    });

    test('the recipient has received it — two ticks', () {
      expect(
        dm(deliveredTo: {them: ms + 1000}).statusOf(message(), me),
        MessageStatus.delivered,
      );
    });

    test('a receipt from before the message says nothing about it', () {
      // Their device was last caught up a minute before this was written, so
      // this particular message has not reached them.
      expect(
        dm(deliveredTo: {them: ms - 60000}).statusOf(message(), me),
        MessageStatus.sent,
      );
    });

    test('the recipient has opened it — read', () {
      expect(
        dm(readBy: {them: ms + 1000}).statusOf(message(), me),
        MessageStatus.read,
      );
    });

    test('having read it counts as having received it', () {
      // The website never writes a delivery receipt, and a chat opened straight
      // from a push notification skips the list that would have written one.
      // Neither should strand a read message on a single tick.
      expect(
        dm(readBy: {them: ms + 1000}, deliveredTo: const {})
            .statusOf(message(), me),
        MessageStatus.read,
      );
    });

    test('server time wins over the sender\'s own clock', () {
      // A phone set ten minutes fast writes a timestamp no receipt can ever
      // reach. The server stamp on the same message is what both sides agree on.
      final skewed = message(
        at: sentAt.add(const Duration(minutes: 10)),
        serverAt: sentAt,
      );
      expect(
        dm(deliveredTo: {them: ms + 1000}).statusOf(skewed, me),
        MessageStatus.delivered,
      );
    });

    test('a conversation with nobody else in it never goes past sent', () {
      expect(
        Chat(id: 'c', type: ChatType.dm, members: const [me])
            .statusOf(message(), me),
        MessageStatus.sent,
      );
    });
  });

  group('Chat.statusOf in a group', () {
    Chat group({
      Map<String, int> readBy = const {},
      Map<String, int> deliveredTo = const {},
    }) =>
        Chat(
          id: 'g1',
          type: ChatType.group,
          members: const [me, them, third],
          readBy: readBy,
          deliveredTo: deliveredTo,
        );

    test('two ticks mean the whole group has it, not just somebody', () {
      expect(
        group(deliveredTo: {them: ms + 1000}).statusOf(message(), me),
        MessageStatus.sent,
      );
      expect(
        group(deliveredTo: {them: ms + 1000, third: ms + 2000})
            .statusOf(message(), me),
        MessageStatus.delivered,
      );
    });

    test('blue means everybody read it', () {
      expect(
        group(
          readBy: {them: ms + 1000},
          deliveredTo: {them: ms + 1000, third: ms + 1000},
        ).statusOf(message(), me),
        MessageStatus.delivered,
      );
      expect(
        group(readBy: {them: ms + 1000, third: ms + 1000})
            .statusOf(message(), me),
        MessageStatus.read,
      );
    });
  });

  group('Chat.admins', () {
    Chat group({
      String? groupAdmin,
      List<String> groupAdmins = const [],
      List<String> members = const [me, them, third],
      bool locked = false,
    }) =>
        Chat(
          id: 'g1',
          type: ChatType.group,
          members: members,
          groupAdmin: groupAdmin,
          groupAdmins: groupAdmins,
          locked: locked,
        );

    test('a group made before the list existed still has its founder', () {
      final chat = group(groupAdmin: me);
      expect(chat.admins, [me]);
      expect(chat.isAdmin(me), isTrue);
      expect(chat.isAdmin(them), isFalse);
    });

    test('several people can hold it at once', () {
      final chat = group(groupAdmin: me, groupAdmins: [me, them]);
      expect(chat.admins, [me, them]);
      expect(chat.isAdmin(them), isTrue);
    });

    test('the founder is listed once, not twice', () {
      expect(group(groupAdmin: me, groupAdmins: [me]).admins, [me]);
    });

    test('the founder is listed even when only the new field names them', () {
      expect(group(groupAdmins: [them]).admins, [them]);
    });

    test('somebody who has left the group is no longer an admin of it', () {
      final chat = group(
        groupAdmin: 'gone',
        groupAdmins: ['gone', them],
        members: const [me, them],
      );
      expect(chat.admins, [them]);
      expect(chat.isAdmin('gone'), isFalse);
    });

    test('a locked group takes posts from any of its admins', () {
      final chat = group(groupAdmin: me, groupAdmins: [me, them], locked: true);
      expect(chat.canPost(me), isTrue);
      expect(chat.canPost(them), isTrue);
      expect(chat.canPost(third), isFalse);
    });

    test('an unlocked group takes posts from everyone', () {
      final chat = group(groupAdmin: me);
      expect(chat.canPost(third), isTrue);
    });
  });

  group('Chat.fromMap', () {
    test('reads both admin spellings', () {
      final chat = Chat.fromMap('g1', {
        'type': 'group',
        'members': [me, them],
        'groupAdmin': me,
        'groupAdmins': [me, them],
      });
      expect(chat.groupAdmin, me);
      expect(chat.admins, [me, them]);
    });

    test('reads delivery receipts alongside read receipts', () {
      final chat = Chat.fromMap('c1', {
        'type': 'dm',
        'members': [me, them],
        'deliveredTo': {them: ms},
        'readBy': {them: ms},
      });
      expect(chat.deliveredTo[them], ms);
      expect(chat.readBy[them], ms);
    });

    test('a document with neither field is simply nobody-has-it-yet', () {
      final chat = Chat.fromMap('c1', {
        'type': 'dm',
        'members': [me, them],
      });
      expect(chat.deliveredTo, isEmpty);
      expect(chat.admins, isEmpty);
      expect(chat.statusOf(message(), me), MessageStatus.sent);
    });
  });

  group('ChatMessage', () {
    test('carries the client id back for matching the optimistic copy', () {
      final parsed = ChatMessage.fromMap('m1', {
        'text': 'hi',
        'senderId': me,
        'clientId': 'pending-123',
      });
      expect(parsed.clientId, 'pending-123');
    });

    test('receipts are measured against server time when there is any', () {
      final parsed = ChatMessage.fromMap('m1', {
        'text': 'hi',
        'senderId': me,
        'timestamp': ms + 600000,
        'serverTimestamp': ms,
      });
      expect(parsed.sentAt?.millisecondsSinceEpoch, ms + 600000);
      expect(parsed.receiptTime?.millisecondsSinceEpoch, ms);
    });

    test('and against the sender\'s clock when there is not', () {
      final parsed = ChatMessage.fromMap('m1', {
        'text': 'hi',
        'senderId': me,
        'timestamp': ms,
      });
      expect(parsed.receiptTime?.millisecondsSinceEpoch, ms);
    });

    test('an upload keeps its identity as its progress moves', () {
      final pending = ChatMessage(
        id: 'pending-1',
        kind: MessageKind.file,
        text: '',
        clientId: 'pending-1',
        serverSentAt: sentAt,
        pending: true,
      );
      final moved = pending.withProgress(0.5);
      expect(moved.uploadProgress, 0.5);
      expect(moved.clientId, 'pending-1');
      expect(moved.serverSentAt, sentAt);
    });
  });
}
