import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../data/repositories/chat_repository.dart';
import '../../data/services/api_client.dart' show ApiException;
import '../../domain/models/chat.dart';
import '../core/format.dart';
import '../core/state/presence_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import 'chat_screen.dart' show ChatAvatar;
import 'group_settings_screen.dart';
import 'user_profile_sheet.dart';
import 'widgets/chat_composer.dart';
import 'widgets/message_bubble.dart';
import 'widgets/typing_indicator.dart';

/// One conversation.
///
/// Port of the thread half of `ChatView`: swipe-to-reply, quoted messages that
/// jump to the original, attachments and voice notes, reactions, read ticks,
/// date separators and multi-select delete.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _composer = TextEditingController();

  /// Positioned rather than a plain controller: jumping to a quoted message
  /// needs to scroll to a known index, which an offset-based controller cannot
  /// do without measuring every bubble above it.
  final _listController = ItemScrollController();
  final _positionListener = ItemPositionsListener.create();

  StreamSubscription<Chat?>? _chatSub;
  StreamSubscription<List<ChatMessage>>? _messageSub;

  Chat? _chat;
  List<ChatMessage> _messages = const [];

  /// Shown immediately, before the write lands.
  final List<ChatMessage> _pending = [];

  QuotedMessage? _replyTo;
  Timer? _typingTimer;

  /// Fires when the other side's typing marker goes stale, so the dots come off.
  Timer? _typistExpiry;

  bool _sending = false;

  /// The message flashing after being jumped to, and the timer clearing it.
  String? _highlighted;
  Timer? _highlightTimer;

  bool _selectionMode = false;
  final Set<String> _selected = {};

  /// Held rather than looked up in `dispose` — see the note on the chat list.
  PresenceController? _presence;

  static const _reactions = ['👍', '❤️', '😂', '😮', '🙏', '🔥'];

  @override
  void initState() {
    super.initState();
    final chats = context.read<ChatRepository>();

    _chatSub = chats.watchChat(widget.chatId).listen((chat) {
      if (!mounted) return;
      setState(() => _chat = chat);
      _armTypistExpiry(chat);
    });

    _messageSub = chats.watchMessages(widget.chatId).listen((messages) {
      if (!mounted) return;
      final wasAtBottom = _isNearBottom;
      setState(() {
        _messages = messages;
        _retirePending(messages);
      });
      // Only follow the conversation down if they were already at the bottom —
      // yanking someone out of the history they were reading is worse than
      // missing a message by one scroll.
      if (wasAtBottom) _scrollToBottom();
      _markReadThrough(messages);
    });

    final uid = context.read<SessionController>().account?.uid;
    if (uid != null) unawaited(chats.markRead(widget.chatId, uid));
  }

  /// Drops the optimistic copies of messages that have now landed.
  ///
  /// Matched on the id the copy was given, which the stored message carries back
  /// in `clientId`. Matching on the text instead — as this used to — retired the
  /// wrong bubble when the same thing was sent twice, and retired nothing at all
  /// for an attachment, so the thread briefly held both the uploading copy and
  /// the real one and then lost a row from under the scroll position.
  void _retirePending(List<ChatMessage> messages) {
    if (_pending.isEmpty) return;

    final landed = <String>{
      for (final message in messages)
        if (message.clientId != null) message.clientId!,
    };

    _pending.removeWhere(
      (p) =>
          landed.contains(p.id) ||
          // Messages written by an older build of the app carry no client id.
          messages.any(
            (m) =>
                m.clientId == null &&
                m.senderId == p.senderId &&
                m.text == p.text,
          ),
    );
  }

  /// The newest foreign message this student has been stamped as having read.
  ///
  /// Held so a conversation somebody is sitting inside stamps once per arrival
  /// rather than once per rebuild.
  int _readThrough = 0;

  /// Tells the senders their messages have been read, while the thread is open.
  ///
  /// Opening the screen is not enough on its own: a student who leaves the
  /// conversation on screen and keeps reading was never stamped again, so
  /// everything that arrived after they walked in stayed on two grey ticks for
  /// the person who sent it.
  void _markReadThrough(List<ChatMessage> messages) {
    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return;

    var newest = 0;
    for (final message in messages) {
      if (message.senderId == null || message.senderId == uid) continue;
      final at = message.receiptTime?.millisecondsSinceEpoch ?? 0;
      if (at > newest) newest = at;
    }
    if (newest <= _readThrough) return;

    _readThrough = newest;
    unawaited(context.read<ChatRepository>().markRead(widget.chatId, uid));
  }

  bool get _isNearBottom {
    final positions = _positionListener.itemPositions.value;
    if (positions.isEmpty) return true;
    final last = positions
        .map((p) => p.index)
        .reduce((a, b) => a > b ? a : b);
    return last >= _visible.length - 2;
  }

  /// True while a scroll animation is in flight, and what to do when it lands.
  ///
  /// `ScrollablePositionedList` animates by building a second copy of the list
  /// and cross-fading across to it. A second animation started before the first
  /// has finished strands both copies part-way, and the thread draws as an empty
  /// box that only comes back by leaving the conversation and opening it again —
  /// which is precisely what sending a message did, because the send scrolls once
  /// and the message landing a moment later scrolls again.
  bool _scrolling = false;
  VoidCallback? _queuedScroll;

  void _scrollToBottom() => _scrollTo(() => _visible.length - 1);

  /// Animates to an index, one animation at a time.
  ///
  /// [index] is evaluated after the frame rather than passed as a number: the row
  /// being scrolled to is usually the one the same `setState` has just added, and
  /// the list may have moved on again by the time the animation is allowed to
  /// start. Anything asked for while an animation is running is collapsed into a
  /// single jump at the end — instant, and with no second list to strand.
  void _scrollTo(
    int Function() index, {
    double alignment = 0,
    Duration duration = Motion.base,
    Curve curve = Motion.enter,
  }) {
    if (_scrolling) {
      _queuedScroll = () => _jumpTo(index(), alignment);
      return;
    }
    _scrolling = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted || !_listController.isAttached) return;
        final at = index();
        if (at < 0) return;
        await _listController
            .scrollTo(
              index: at,
              duration: duration,
              curve: curve,
              alignment: alignment,
            )
            // A watchdog, not a feature: an animation interrupted at the wrong
            // moment can leave its future hanging, and a gate that never opens
            // again would quietly stop the thread following new messages down.
            .timeout(duration + const Duration(seconds: 2), onTimeout: () {});
      } catch (_) {
        // The list went away mid-animation. There is nothing to say about it.
      } finally {
        _scrolling = false;
      }

      final queued = _queuedScroll;
      _queuedScroll = null;
      queued?.call();
    });
  }

  void _jumpTo(int index, double alignment) {
    if (!mounted || !_listController.isAttached || index < 0) return;
    _listController.jumpTo(index: index, alignment: alignment);
  }

  /// Scrolls to the message a reply quotes, and flashes it.
  void _jumpToQuoted(QuotedMessage quoted) {
    if (!_visible.any((m) => m.id == quoted.messageId)) {
      // Either it is older than the window we loaded, or the reply came from
      // another conversation — the web says the same thing here.
      showToast('That message is not in this part of the conversation.');
      return;
    }

    _scrollTo(
      () => _visible.indexWhere((m) => m.id == quoted.messageId),
      // Lands it in the middle rather than jammed against the top edge.
      alignment: 0.35,
      duration: Motion.slow,
      curve: Motion.emphasized,
    );

    _highlightTimer?.cancel();
    setState(() => _highlighted = quoted.messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _highlighted = null);
    });
  }

  @override
  void dispose() {
    // Before the subscriptions go: leaving a conversation mid-sentence used to
    // leave the marker behind, and the only thing clearing it was the other
    // client's staleness cutoff.
    _stopTyping();
    _presence?.untrack('chat-${widget.chatId}');
    _chatSub?.cancel();
    _messageSub?.cancel();
    _typistExpiry?.cancel();
    _highlightTimer?.cancel();
    _composer.dispose();
    super.dispose();
  }

  String get _myUid =>
      context.read<SessionController>().account?.uid ?? '';

  List<ChatMessage> get _visible => [
        ..._messages.where((m) => m.isVisibleTo(_myUid)),
        ..._pending,
      ];

  /// How often the "still typing" stamp is refreshed.
  ///
  /// Comfortably inside [Chat.typingTimeoutMs] so the other side never sees the
  /// indicator flicker off mid-sentence, and far enough apart that a fast typist
  /// doesn't rewrite the conversation document on every letter — which is a write
  /// per keystroke, billed per keystroke, and re-delivered to everyone in the
  /// chat per keystroke.
  static const _typingRefresh = Duration(seconds: 2);

  /// When the stamp was last written, so [_onTyping] can tell "kept typing" from
  /// "started typing".
  DateTime? _typingSince;

  void _onTyping(String value) {
    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return;
    final chats = context.read<ChatRepository>();

    if (value.trim().isEmpty) {
      _stopTyping();
      return;
    }

    final since = _typingSince;
    if (since == null || DateTime.now().difference(since) >= _typingRefresh) {
      _typingSince = DateTime.now();
      unawaited(chats.setTyping(widget.chatId, uid, true));
    }

    // Clears the marker when they stop typing without sending — otherwise the
    // other side waits on a reply that is never coming.
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  /// Rebuilds when the oldest typing marker goes stale.
  ///
  /// A marker is only cleared by the client that set it, so a browser closed
  /// mid-sentence leaves one behind for good. [Chat.typistsOtherThan] already
  /// ignores anything past the cutoff — but nothing writes to the document to
  /// trigger the rebuild that would notice, so the dots would sit there forever.
  void _armTypistExpiry(Chat? chat) {
    _typistExpiry?.cancel();
    _typistExpiry = null;
    if (chat == null) return;

    final uid = context.read<SessionController>().account?.uid;
    final stamps = [
      for (final entry in chat.typing.entries)
        if (entry.key != uid) entry.value,
    ];
    if (stamps.isEmpty) return;

    final newest = stamps.reduce((a, b) => a > b ? a : b);
    final remaining = newest +
        Chat.typingTimeoutMs -
        DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return;

    _typistExpiry = Timer(
      Duration(milliseconds: remaining + 100),
      () {
        if (mounted) setState(() {});
      },
    );
  }

  /// Drops this student's typing marker. Safe to call when there isn't one.
  void _stopTyping() {
    _typingTimer?.cancel();
    _typingTimer = null;
    if (_typingSince == null) return;
    _typingSince = null;

    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return;
    unawaited(context.read<ChatRepository>().setTyping(widget.chatId, uid, false));
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    final chat = _chat;
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (text.isEmpty || chat == null || uid == null || _sending) return;

    if (!chat.canPost(uid)) {
      showToast('Only group admins can post here.');
      return;
    }

    final reply = _replyTo;
    final localId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: localId,
      kind: MessageKind.text,
      text: text,
      senderId: uid,
      senderName: session.profile?.displayName ?? 'You',
      sentAt: DateTime.now(),
      replyTo: reply,
      pending: true,
    );

    setState(() {
      _sending = true;
      _composer.clear();
      _replyTo = null;
      _pending.add(optimistic);
    });
    // The send itself deletes the marker in the same batch, so this only has to
    // forget that we wrote one.
    _typingTimer?.cancel();
    _typingSince = null;
    _scrollToBottom();

    try {
      await context.read<ChatRepository>().sendMessage(
            widget.chatId,
            chat: chat,
            senderId: uid,
            senderName: session.profile?.displayName ?? 'Student',
            senderPhoto: session.profile?.avatarUrl,
            text: text,
            replyTo: reply,
            clientId: localId,
          );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pending.remove(optimistic);
        // The text goes back in the box rather than being lost with the bubble.
        _composer.text = text;
        _replyTo = reply;
      });
      showToast(
        error is ApiException ? error.message : 'Message not sent. Try again.',
        variant: ToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Uploads and posts an attachment, with the bubble already on screen.
  Future<void> _sendAttachment(PendingAttachment attachment) async {
    final chat = _chat;
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (chat == null || uid == null) return;

    if (!chat.canPost(uid)) {
      showToast('Only group admins can post here.');
      return;
    }

    final category = MediaCategory.fromMime(attachment.mimeType);
    final reply = _replyTo;
    final localId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    var optimistic = ChatMessage(
      id: localId,
      kind: MessageKind.file,
      text: category.label,
      senderId: uid,
      senderName: session.profile?.displayName ?? 'You',
      sentAt: DateTime.now(),
      replyTo: reply,
      // Shown from the local file, so a photo appears the instant it is picked
      // rather than after the round trip.
      mediaUrl: attachment.file.path,
      fileName: attachment.fileName,
      fileType: attachment.mimeType,
      category: category,
      pending: true,
      uploadProgress: 0,
    );

    setState(() {
      _replyTo = null;
      _pending.add(optimistic);
    });
    _scrollToBottom();

    try {
      await context.read<ChatRepository>().sendAttachment(
        widget.chatId,
        chat: chat,
        file: attachment.file,
        fileName: attachment.fileName,
        mimeType: attachment.mimeType,
        senderId: uid,
        senderName: session.profile?.displayName ?? 'Student',
        senderPhoto: session.profile?.avatarUrl,
        replyTo: reply,
        clientId: localId,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            final at = _pending.indexWhere((m) => m.id == localId);
            if (at >= 0) {
              optimistic = optimistic.withProgress(progress);
              _pending[at] = optimistic;
            }
          });
        },
      );
      if (mounted) {
        setState(() => _pending.removeWhere((m) => m.id == localId));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _pending.removeWhere((m) => m.id == localId));
      showToast(
        error is ApiException
            ? error.message
            : 'Could not send that file. Check your connection.',
        variant: ToastVariant.error,
      );
    }
  }

  Future<void> _openMessageMenu(ChatMessage message) async {
    final uid = _myUid;
    if (uid.isEmpty || message.pending) return;
    final isMine = message.senderId == uid;
    final chats = context.read<ChatRepository>();

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.s4,
                vertical: Tokens.s3,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in _reactions)
                    InkWell(
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        chats.toggleReaction(
                          widget.chatId,
                          message,
                          uid: uid,
                          emoji: emoji,
                        );
                      },
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _startReply(message);
              },
            ),
            if ((_chat?.isGroup ?? false) &&
                !isMine &&
                message.senderId != null) ...[
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(
                  'View ${(message.senderName ?? 'contact').split(' ').first}',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showUserProfile(
                    context,
                    uid: message.senderId!,
                    fallbackName: message.senderName,
                    fallbackPhoto: message.senderPhoto,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward_to_inbox_rounded),
                title: const Text('Reply privately'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _replyPrivately(message);
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: const Text('Select messages'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setState(() {
                  _selectionMode = true;
                  _selected.add(message.id);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_rounded),
              title: const Text('Delete for me'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                chats.deleteForMe(widget.chatId, message.id, uid);
              },
            ),
            if (isMine && !message.deleted)
              ListTile(
                leading: Icon(
                  Icons.delete_rounded,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  'Delete for everyone',
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  chats.deleteForEveryone(widget.chatId, message.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _startReply(ChatMessage message) => setState(
        () => _replyTo = QuotedMessage(
          messageId: message.id,
          text: message.displayText,
          senderName: message.senderName,
        ),
      );

  /// Opens (or starts) the DM with this sender, carrying the quote across.
  Future<void> _replyPrivately(ChatMessage message) async {
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    final targetUid = message.senderId;
    if (uid == null || targetUid == null || targetUid == uid) return;

    final chats = context.read<ChatRepository>();
    final navigator = Navigator.of(context);

    try {
      final chatId = await chats.openDirectMessage(
        existing: await chats.watchChats(uid).first,
        myUid: uid,
        myName: session.profile?.displayName ?? 'Student',
        myPhoto: session.profile?.avatarUrl,
        contact: ChatContact(
          uid: targetUid,
          name: message.senderName ?? 'Student',
          photo: message.senderPhoto,
        ),
      );
      if (!mounted) return;
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationScreen(chatId: chatId),
        ),
      );
    } catch (_) {
      if (mounted) {
        showToast(
          'Could not open that conversation.',
          variant: ToastVariant.error,
        );
      }
    }
  }

  Future<void> _deleteSelected() async {
    final uid = _myUid;
    if (uid.isEmpty || _selected.isEmpty) return;
    final ids = _selected.toList();
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
    try {
      await context
          .read<ChatRepository>()
          .deleteManyForMe(widget.chatId, ids, uid);
    } catch (_) {
      if (mounted) {
        showToast('Could not delete those.', variant: ToastVariant.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uid = _myUid;
    final chat = _chat;
    final visible = _visible;
    final typists = chat?.typistsOtherThan(uid) ?? const [];
    final canPost = chat?.canPost(uid) ?? true;

    final presenceController = context.watch<PresenceController>();
    _presence = presenceController;
    presenceController.track(
      'chat-${widget.chatId}',
      chat?.othersThan(uid) ?? const <String>[],
    );

    // Only for a direct message: in a group the header counts heads instead, and
    // "last seen" would be about whichever member happened to sort first.
    final otherUid = chat != null && !chat.isGroup ? chat.otherMember(uid) : null;
    final presence = presenceController.presenceOf(otherUid);
    final online = otherUid != null && presence.isOnline;

    // What is happening now beats what happened last: typing, then presence,
    // then the standing fact about the room. The same precedence as the website.
    final status = typists.isNotEmpty
        ? '${typists.first.split(' ').first} is typing…'
        : chat == null
            ? ''
            : chat.isGroup
                ? '${chat.members.length} members'
                : online
                    ? 'Online'
                    : lastSeenLabel(presence.lastSeen);

    return PopScope(
      // Selection mode is a state to back out of before the screen itself.
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() {
            _selectionMode = false;
            _selected.clear();
          });
        }
      },
      child: Scaffold(
        appBar: _selectionMode
            ? AppBar(
                leading: IconButton(
                  onPressed: () => setState(() {
                    _selectionMode = false;
                    _selected.clear();
                  }),
                  icon: const Icon(Icons.close_rounded),
                ),
                title: Text('${_selected.length} selected'),
                actions: [
                  IconButton(
                    onPressed: _selected.isEmpty ? null : _deleteSelected,
                    icon: const Icon(Icons.delete_rounded),
                    tooltip: 'Delete for me',
                  ),
                ],
              )
            : AppBar(
                titleSpacing: 0,
                title: chat == null
                    ? const Text('Loading…')
                    : InkWell(
                        // A group header opens the group; a direct message opens
                        // the person it is with.
                        onTap: chat.isGroup
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => GroupSettingsScreen(
                                      chatId: widget.chatId,
                                    ),
                                  ),
                                )
                            : otherUid == null
                                ? null
                                : () => showUserProfile(
                                      context,
                                      uid: otherUid,
                                      fallbackName: chat.titleFor(uid),
                                      fallbackPhoto: chat.avatarFor(uid),
                                      allowMessage: false,
                                    ),
                        child: Row(
                          children: [
                            ChatAvatar(
                              url: presence.photo ?? chat.avatarFor(uid),
                              fallback: chat.titleFor(uid),
                              isGroup: chat.isGroup,
                              size: 34,
                              online: online,
                            ),
                            const SizedBox(width: Tokens.s3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    chat.titleFor(uid),
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Row(
                                    children: [
                                      if (online && typists.isEmpty) ...[
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: BlueprintPalette.success,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                      ],
                                      Flexible(
                                        child: Text(
                                          status,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: online &&
                                                    typists.isEmpty
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                            color: typists.isNotEmpty
                                                ? scheme.primary
                                                : online
                                                    ? BlueprintPalette.success
                                                    : scheme.onSurfaceVariant,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                actions: [
                  if (chat?.isGroup ?? false)
                    IconButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              GroupSettingsScreen(chatId: widget.chatId),
                        ),
                      ),
                      icon: const Icon(Icons.info_outline_rounded),
                      tooltip: 'Group info',
                    ),
                ],
              ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(Tokens.s6),
                          child: Text(
                            'No messages yet — say hello.',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ScrollablePositionedList.builder(
                        itemScrollController: _listController,
                        itemPositionsListener: _positionListener,
                        padding: const EdgeInsets.fromLTRB(
                          Tokens.s2,
                          Tokens.s3,
                          Tokens.s2,
                          Tokens.s2,
                        ),
                        initialScrollIndex:
                            visible.isEmpty ? 0 : visible.length - 1,
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final message = visible[i];
                          final previous = i == 0 ? null : visible[i - 1];
                          final next =
                              i == visible.length - 1 ? null : visible[i + 1];
                          final isMine = message.senderId == uid;
                          final isGroup = chat?.isGroup ?? false;

                          return Column(
                            children: [
                              if (message.sentAt != null &&
                                  !DateSeparator.sameDay(
                                    previous?.sentAt,
                                    message.sentAt,
                                  ))
                                DateSeparator(date: message.sentAt!),
                              MessageBubble(
                                message: message,
                                isMine: isMine,
                                chat: chat,
                                myUid: uid,
                                // The name heads a run; the avatar tails it, so
                                // a block of messages reads as one person
                                // speaking rather than a list of cards.
                                showSender: isGroup &&
                                    !isMine &&
                                    previous?.senderId != message.senderId,
                                showAvatar: isGroup &&
                                    !isMine &&
                                    next?.senderId != message.senderId,
                                selectionMode: _selectionMode,
                                selected: _selected.contains(message.id),
                                highlighted: _highlighted == message.id,
                                onReply: () => _startReply(message),
                                onLongPress: () => _openMessageMenu(message),
                                onTapQuoted: () =>
                                    _jumpToQuoted(message.replyTo!),
                                onToggleSelect: () => setState(() {
                                  if (!_selected.remove(message.id)) {
                                    _selected.add(message.id);
                                  }
                                  if (_selected.isEmpty) {
                                    _selectionMode = false;
                                  }
                                }),
                                onTapReaction: (emoji) => context
                                    .read<ChatRepository>()
                                    .toggleReaction(
                                      widget.chatId,
                                      message,
                                      uid: uid,
                                      emoji: emoji,
                                    ),
                                onTapSender: () {
                                  final sender = message.senderId;
                                  if (sender == null || sender == uid) return;
                                  showUserProfile(
                                    context,
                                    uid: sender,
                                    fallbackName: message.senderName,
                                    fallbackPhoto: message.senderPhoto,
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
              ),
              // Under the thread rather than inside it: a bubble in the list
              // would push the last message up and steal the scroll position
              // every time somebody paused for breath.
              if (typists.isNotEmpty && !_selectionMode)
                TypingIndicator(names: typists),
              if (_replyTo != null && !_selectionMode)
                _ReplyPreview(
                  quoted: _replyTo!,
                  onCancel: () => setState(() => _replyTo = null),
                ),
              if (!_selectionMode)
                ChatComposer(
                  controller: _composer,
                  enabled: canPost,
                  sending: _sending,
                  onChanged: _onTyping,
                  onSend: _send,
                  onAttach: _sendAttachment,
                  lockedNote: canPost
                      ? null
                      : 'Only group admins can post in this group.',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.quoted, required this.onCancel});

  final QuotedMessage quoted;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, 4),
      padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Tokens.rSm),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${quoted.senderName ?? 'someone'}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
                Text(
                  quoted.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 17),
            tooltip: 'Cancel reply',
          ),
        ],
      ),
    );
  }
}
