import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/chat_repository.dart';
import '../../domain/models/chat.dart';
import '../core/state/dashboard_controller.dart';
import '../core/state/presence_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/skeleton.dart';
import 'conversation_screen.dart';
import 'widgets/contact_search_list.dart';

/// Messages — the conversation list.
///
/// Port of the list half of `ChatView`. Tapping a row opens the conversation on
/// its own route rather than in a side panel: a phone has no room for both, and
/// the back gesture is the "close chat" a student already knows.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  StreamSubscription<List<Chat>>? _subscription;
  List<Chat>? _chats;
  String _search = '';

  /// Held rather than looked up in `dispose`: on sign-out the providers above
  /// are torn down in the same frame, and reaching back up through a deactivated
  /// context is how that becomes a crash instead of a sign-out.
  PresenceController? _presence;

  @override
  void initState() {
    super.initState();
    final uid = context.read<SessionController>().account?.uid;
    if (uid != null) {
      _subscription = context
          .read<ChatRepository>()
          .watchChats(uid)
          .listen(
            (chats) {
              if (!mounted) return;
              setState(() => _chats = chats);
              _openPendingChat(chats);
            },
            onError: (_) {
              if (mounted) setState(() => _chats = const []);
            },
          );
    }
  }

  /// A chat push was tapped: open that conversation once the list has it.
  void _openPendingChat(List<Chat> chats) {
    final dashboard = context.read<DashboardController>();
    final pending = dashboard.pendingChatId;
    if (pending == null) return;

    final match = chats.where((c) => c.id == pending).firstOrNull;
    if (match == null) return;

    dashboard.consumePendingChatId();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(match);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _presence?.untrack('chat-list');
    super.dispose();
  }

  Future<void> _open(Chat chat) async {
    final uid = context.read<SessionController>().account?.uid;
    if (uid != null) {
      unawaited(context.read<ChatRepository>().markRead(chat.id, uid));
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(chatId: chat.id),
      ),
    );
  }

  /// The compose menu: a direct message, or a new group.
  Future<void> _openComposeMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: const Text('New message'),
              subtitle: const Text('Start a chat with one person'),
              onTap: () => Navigator.of(sheetContext).pop('dm'),
            ),
            ListTile(
              leading: const Icon(Icons.group_add_rounded),
              title: const Text('New group'),
              subtitle: const Text('Study together with your classmates'),
              onTap: () => Navigator.of(sheetContext).pop('group'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'dm') {
      await _startDirectMessage();
    } else {
      await _createGroup();
    }
  }

  Future<void> _startDirectMessage() async {
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null) return;

    final chats = context.read<ChatRepository>();

    // The sheet opens straight away and loads inside itself. Awaiting the
    // directory first meant the compose button did nothing at all for as long as
    // the round trip took, which on a slow connection reads as a dead button.
    final picked = await showModalBottomSheet<ChatContact>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ContactPicker(exclude: {uid}),
    );
    if (picked == null || !mounted) return;

    try {
      final chatId = await chats.openDirectMessage(
        existing: _chats ?? const [],
        myUid: uid,
        myName: session.profile?.displayName ?? 'Student',
        myPhoto: session.profile?.avatarUrl,
        contact: picked,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationScreen(chatId: chatId),
        ),
      );
    } catch (_) {
      if (mounted) {
        showToast(
          'Could not start that conversation.',
          variant: ToastVariant.error,
        );
      }
    }
  }

  Future<void> _createGroup() async {
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null) return;

    final chats = context.read<ChatRepository>();

    final result = await showModalBottomSheet<({String name, List<ChatContact> members})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewGroupSheet(exclude: {uid}),
    );
    if (result == null || !mounted) return;

    try {
      final chatId = await chats.createGroup(
        name: result.name,
        myUid: uid,
        myName: session.profile?.displayName ?? 'Student',
        myPhoto: session.profile?.avatarUrl,
        contacts: result.members,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationScreen(chatId: chatId),
        ),
      );
    } catch (_) {
      if (mounted) {
        showToast('Could not create the group.', variant: ToastVariant.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<SessionController>().account?.uid ?? '';
    final chats = _chats;
    final query = _search.trim().toLowerCase();
    final visible = chats == null
        ? null
        : query.isEmpty
            ? chats
            : chats
                // The last message counts as part of the conversation's name for
                // searching, the same way it does on the website — "that link
                // Ada sent" is how people actually look for a thread.
                .where(
                  (c) =>
                      c.titleFor(uid).toLowerCase().contains(query) ||
                      (c.lastMessage?.text.toLowerCase().contains(query) ??
                          false),
                )
                .toList();

    // One listener per person this student has a direct message open with, held
    // by the controller so the conversation screen reuses the same one.
    final presence = context.watch<PresenceController>();
    _presence = presence;
    presence.track('chat-list', [
      for (final chat in chats ?? const <Chat>[])
        if (!chat.isGroup) ...chat.othersThan(uid),
    ]);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
        children: [
          const PageHeader(
            title: 'Messages',
            subtitle: 'Ask your tutors a question, or study together with your '
                'classmates.',
          ),
          TextField(
            onChanged: (value) => setState(() => _search = value),
            decoration: const InputDecoration(
              hintText: 'Search conversations…',
              prefixIcon: Icon(Icons.search_rounded, size: 19),
              isDense: true,
            ),
          ),
          const SizedBox(height: Tokens.s4),
          if (visible == null)
            const Column(
              children: [
                SkeletonListItem(lines: 2),
                SizedBox(height: Tokens.s3),
                SkeletonListItem(lines: 2),
                SizedBox(height: Tokens.s3),
                SkeletonListItem(lines: 2),
              ],
            )
          else if (visible.isEmpty)
            EmptyState(
              icon: Icons.forum_rounded,
              title: query.isEmpty ? 'No conversations yet' : 'No matches',
              message: query.isEmpty
                  ? 'Start one with a tutor or a classmate — ask about anything '
                      "you're stuck on."
                  : 'No conversation matches "$_search".',
              actionLabel: query.isEmpty ? 'Start a conversation' : null,
              onAction: query.isEmpty ? _openComposeMenu : null,
            )
          else
            for (final chat in visible)
              _ChatRow(
                chat: chat,
                myUid: uid,
                online: !chat.isGroup &&
                    presence.isOnline(chat.otherMember(uid)),
                onTap: () => _open(chat),
              ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openComposeMenu,
        tooltip: 'New conversation',
        child: const Icon(Icons.edit_rounded),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.chat,
    required this.myUid,
    required this.online,
    required this.onTap,
  });

  final Chat chat;
  final String myUid;

  /// Only ever true for a direct message: a group is not a person, and a dot on
  /// one would be claiming something about nobody in particular.
  final bool online;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = chat.unreadFor(myUid);
    final typists = chat.typistsOtherThan(myUid);
    final avatar = chat.avatarFor(myUid);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s3,
            vertical: Tokens.s3,
          ),
          child: Row(
            children: [
              ChatAvatar(
                url: avatar,
                fallback: chat.titleFor(myUid),
                isGroup: chat.isGroup,
                online: online,
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.titleFor(myUid),
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight:
                                  unread > 0 ? FontWeight.w900 : FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chat.lastActivity != null)
                          Text(
                            _when(chat.lastActivity!),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            // What is happening right now beats what was said
                            // last — the same precedence the web uses.
                            typists.isNotEmpty
                                ? '${typists.first} is typing…'
                                : chat.lastMessage?.text ?? 'No messages yet',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: typists.isNotEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              fontWeight: unread > 0
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: typists.isNotEmpty
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: Tokens.s2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime at) {
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    if (sameDay) return DateFormat('HH:mm').format(at);
    if (now.difference(at).inDays < 7) return DateFormat('EEE').format(at);
    return DateFormat('d MMM').format(at);
  }
}

/// A round avatar, falling back to initials when there is no photo.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.url,
    required this.fallback,
    this.isGroup = false,
    this.size = 44,
    this.online = false,
  });

  final String? url;
  final String fallback;
  final bool isGroup;
  final double size;
  final bool online;

  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: url == null
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [BlueprintPalette.b600, BlueprintPalette.b400],
                  )
                : null,
            image: url == null
                ? null
                : DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover),
          ),
          alignment: Alignment.center,
          child: url != null
              ? null
              : isGroup
                  ? Icon(Icons.group_rounded, size: size * 0.45, color: Colors.white)
                  : Text(
                      initialsOf(fallback),
                      style: TextStyle(
                        fontSize: size * 0.34,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
        ),
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: BlueprintPalette.success,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

/// Name a group and choose who is in it.
class _NewGroupSheet extends StatefulWidget {
  const _NewGroupSheet({required this.exclude});

  final Set<String> exclude;

  @override
  State<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<_NewGroupSheet> {
  final _name = TextEditingController();
  final _picked = <ChatContact>[];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toggle(ChatContact contact) => setState(() {
        if (!_picked.any((c) => c.uid == contact.uid)) {
          _picked.add(contact);
        } else {
          _picked.removeWhere((c) => c.uid == contact.uid);
        }
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canCreate = _name.text.trim().isNotEmpty && _picked.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Tokens.s5,
          right: Tokens.s5,
          top: Tokens.s2,
          bottom: Tokens.s4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New group',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: Tokens.s3),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Group name',
                hintText: 'e.g. Physics study group',
                isDense: true,
              ),
            ),
            const SizedBox(height: Tokens.s3),
            Text(
              _picked.isEmpty
                  ? 'Add members'
                  : '${_picked.length} member${_picked.length == 1 ? '' : 's'} added',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Tokens.s2),
            Flexible(
              child: ContactSearchList(
                multiSelect: true,
                exclude: widget.exclude,
                selected: {for (final c in _picked) c.uid},
                onTap: _toggle,
              ),
            ),
            const SizedBox(height: Tokens.s3),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canCreate
                    ? () => Navigator.of(context).pop(
                          (name: _name.text.trim(), members: _picked),
                        )
                    : null,
                icon: const Icon(Icons.group_add_rounded, size: 18),
                label: Text(
                  _name.text.trim().isEmpty
                      ? 'Name the group'
                      : _picked.isEmpty
                          ? 'Add someone'
                          : 'Create group',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who to message.
class _ContactPicker extends StatelessWidget {
  const _ContactPicker({required this.exclude});

  final Set<String> exclude;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Tokens.s5,
          right: Tokens.s5,
          top: Tokens.s2,
          bottom: Tokens.s4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New conversation',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: Tokens.s3),
            Flexible(
              child: ContactSearchList(
                autofocus: true,
                exclude: exclude,
                onTap: (contact) => Navigator.of(context).pop(contact),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
