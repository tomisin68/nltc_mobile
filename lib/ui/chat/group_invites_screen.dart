import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/chat_repository.dart';
import '../../data/services/api_client.dart' show ApiException;
import '../../domain/models/chat.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/empty_state.dart';
import 'chat_screen.dart' show ChatAvatar;
import 'conversation_screen.dart';

/// Groups this student has been invited to and has not answered.
///
/// The whole reason this screen exists: being added to a group used to be
/// something that happened to you, with the first you knew of it being a
/// stranger's conversation in your list. Now somebody asks. Until the answer is
/// yes the group is not in the conversation list, its messages are unreadable,
/// and no push from it arrives — the invitation is all there is.
class GroupInvitesScreen extends StatefulWidget {
  const GroupInvitesScreen({super.key, required this.invites});

  /// The unanswered invitations, as of the moment the tray was opened. Held as
  /// a parameter rather than re-subscribed, exactly like the message requests
  /// tray: the list screen holds the live stream, and answering pops back to it.
  final List<Chat> invites;

  @override
  State<GroupInvitesScreen> createState() => _GroupInvitesScreenState();
}

class _GroupInvitesScreenState extends State<GroupInvitesScreen> {
  late final List<Chat> _invites = [...widget.invites];

  /// Ids currently being written, so a double-tap can't fire two answers.
  final _busy = <String>{};

  Future<void> _accept(Chat chat) async {
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null || !_busy.add(chat.id)) return;
    setState(() {});

    try {
      await context.read<ChatRepository>().acceptGroupInvite(
            chat.id,
            uid: uid,
            name: session.profile?.displayName ?? 'Someone',
          );
      if (!mounted) return;
      setState(() => _invites.removeWhere((c) => c.id == chat.id));
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationScreen(chatId: chat.id),
        ),
      );
    } catch (error) {
      if (mounted) {
        showToast(
          error is ApiException ? error.message : 'Could not join that group.',
          variant: ToastVariant.error,
        );
      }
    } finally {
      _busy.remove(chat.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _decline(Chat chat) async {
    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Decline ${chat.name ?? 'this group'}?'),
        content: const Text(
          'Nobody in the group is told. You can be invited again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!_busy.add(chat.id)) return;
    setState(() {});

    try {
      await context.read<ChatRepository>().declineGroupInvite(
            chat.id,
            uid: uid,
          );
      if (!mounted) return;
      setState(() => _invites.removeWhere((c) => c.id == chat.id));
      showToast('Invitation declined.');
    } catch (error) {
      if (mounted) {
        showToast(
          error is ApiException
              ? error.message
              : 'Could not decline that invitation.',
          variant: ToastVariant.error,
        );
      }
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
      appBar: AppBar(title: const Text('Group invitations')),
      body: _invites.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(Tokens.s4),
              child: EmptyState(
                icon: Icons.group_add_rounded,
                title: 'No invitations',
                message: 'When a classmate invites you to a study group, it '
                    'waits here until you answer.',
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
                  'You are only in a group once you accept. Until then nobody '
                  'in it can message you.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Tokens.s4),
                for (final chat in _invites)
                  _InviteCard(
                    chat: chat,
                    myUid: uid,
                    busy: _busy.contains(chat.id),
                    onAccept: () => _accept(chat),
                    onDecline: () => _decline(chat),
                  ),
              ],
            ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
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
    final title = chat.name ?? 'Group';
    final inviter = chat.inviterNameFor(myUid);
    final description = chat.description?.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s3),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChatAvatar(
                  url: chat.groupPhoto,
                  fallback: title,
                  isGroup: true,
                  size: 42,
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // Who is asking is the thing that decides the answer,
                        // so it goes above the fold and not in a footnote.
                        inviter == null
                            ? 'You have been invited'
                            : '$inviter invited you',
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
              ],
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: Tokens.s3),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Tokens.s2),
            Row(
              children: [
                Icon(
                  Icons.group_rounded,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  chat.members.length == 1
                      ? '1 member'
                      : '${chat.members.length} members',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
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
                        : const Text('Join'),
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
