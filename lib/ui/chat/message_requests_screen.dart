import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/chat_repository.dart';
import '../../domain/models/chat.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/empty_state.dart';
import 'chat_screen.dart' show ChatAvatar;
import 'conversation_screen.dart';

/// The tray of first messages from students this one has never spoken to.
///
/// Held separately from the conversation list on purpose. Anyone on the
/// platform can open a DM with anyone else, and a student should be able to see
/// who is asking, and what about, without that arriving in the same list as
/// their study group — and without having to explain themselves to decline it.
class MessageRequestsScreen extends StatefulWidget {
  const MessageRequestsScreen({super.key, required this.requests});

  /// The pending conversations, as of the moment the tray was opened. Kept as
  /// a parameter rather than re-subscribed: the list screen already holds the
  /// live stream, and answering a request here pops straight back to it.
  final List<Chat> requests;

  @override
  State<MessageRequestsScreen> createState() => _MessageRequestsScreenState();
}

class _MessageRequestsScreenState extends State<MessageRequestsScreen> {
  late final List<Chat> _requests = [...widget.requests];

  /// Ids currently being written, so a double-tap can't fire two updates.
  final _busy = <String>{};

  Future<void> _accept(Chat chat) async {
    if (!_busy.add(chat.id)) return;
    setState(() {});
    try {
      await context.read<ChatRepository>().acceptRequest(chat.id);
      if (!mounted) return;
      setState(() => _requests.removeWhere((c) => c.id == chat.id));
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationScreen(chatId: chat.id),
        ),
      );
    } catch (_) {
      if (mounted) showToast('Could not accept that request. Try again.');
    } finally {
      _busy.remove(chat.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _decline(Chat chat, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline this request?'),
        content: Text(
          '$title will not be told, and will not be able to message you '
          'again. Their messages are removed from your list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!_busy.add(chat.id)) return;
    setState(() {});
    try {
      await context.read<ChatRepository>().declineRequest(chat.id);
      if (!mounted) return;
      setState(() => _requests.removeWhere((c) => c.id == chat.id));
      showToast('Request declined.');
    } catch (_) {
      if (mounted) showToast('Could not decline that request. Try again.');
    } finally {
      _busy.remove(chat.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<SessionController>().account?.uid ?? '';
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Message requests')),
      body: _requests.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(Tokens.s4),
              child: EmptyState(
                icon: Icons.mark_email_read_rounded,
                title: 'No requests',
                message: 'When someone you have not spoken to messages you, '
                    'it waits here first.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Tokens.s4,
                Tokens.s4,
                Tokens.s4,
                Tokens.s10,
              ),
              children: [
                Text(
                  'These students have messaged you for the first time. '
                  'Accepting moves the conversation into your list.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Tokens.s4),
                for (final chat in _requests)
                  _RequestCard(
                    chat: chat,
                    myUid: uid,
                    busy: _busy.contains(chat.id),
                    onAccept: () => _accept(chat),
                    onDecline: () => _decline(chat, chat.titleFor(uid)),
                  ),
              ],
            ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.chat,
    required this.myUid,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final Chat chat;
  final String myUid;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = chat.titleFor(myUid);
    final preview = chat.lastMessage?.text.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s3),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChatAvatar(
                  url: chat.avatarFor(myUid),
                  fallback: title,
                  size: 42,
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (preview != null && preview.isNotEmpty) ...[
              const SizedBox(height: Tokens.s3),
              Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Tokens.s4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onDecline,
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : onAccept,
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
