import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/chat_repository.dart';
import '../../domain/models/chat.dart';
import '../core/format.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import 'chat_screen.dart' show ChatAvatar;
import 'conversation_screen.dart';

/// Opens the card for one person: their photo, name, role and whether they are
/// about, with a way to start a conversation.
///
/// Reached from anywhere a person appears — the header of a direct message, the
/// avatar or name above a message in a group, a row in the member list. A name
/// in a group chat is often the only thing a student knows about a classmate,
/// and tapping it is the obvious way to find out who they are.
Future<void> showUserProfile(
  BuildContext context, {
  required String uid,
  String? fallbackName,
  String? fallbackPhoto,

  /// False when the profile was opened from inside that person's own
  /// conversation — offering to open the chat you are already reading is noise.
  bool allowMessage = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _UserProfileSheet(
      uid: uid,
      fallbackName: fallbackName,
      fallbackPhoto: fallbackPhoto,
      allowMessage: allowMessage,
    ),
  );
}

class _UserProfileSheet extends StatefulWidget {
  const _UserProfileSheet({
    required this.uid,
    required this.fallbackName,
    required this.fallbackPhoto,
    required this.allowMessage,
  });

  final String uid;

  /// What the chat already knows, shown until the profile itself arrives so the
  /// sheet opens with a name in it rather than a spinner.
  final String? fallbackName;
  final String? fallbackPhoto;

  final bool allowMessage;

  @override
  State<_UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends State<_UserProfileSheet> {
  StreamSubscription<ChatContact?>? _subscription;

  ChatContact? _contact;
  bool _loaded = false;
  bool _opening = false;

  /// Re-reads the "last seen" line as it ages, the same way the chat header does.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _subscription =
        context.read<ChatRepository>().watchContact(widget.uid).listen(
      (contact) {
        if (!mounted) return;
        setState(() {
          _contact = contact;
          _loaded = true;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _loaded = true);
      },
    );
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  /// Opens the conversation with this person, creating it if there isn't one.
  Future<void> _message() async {
    final session = context.read<SessionController>();
    final myUid = session.account?.uid;
    final contact = _contact;
    if (myUid == null || contact == null || _opening) return;

    setState(() => _opening = true);
    final chats = context.read<ChatRepository>();
    final navigator = Navigator.of(context);

    try {
      final chatId = await chats.openDirectMessage(
        existing: await chats.watchChats(myUid).first,
        myUid: myUid,
        myName: session.profile?.displayName ?? 'Student',
        myPhoto: session.profile?.avatarUrl,
        contact: contact,
      );
      if (!mounted) return;
      // The sheet closes before the conversation opens, so backing out of the
      // conversation lands on whatever it was opened from rather than on a sheet
      // about somebody the student has just finished talking to.
      navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationScreen(chatId: chatId),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _opening = false);
      showToast(
        'Could not open that conversation.',
        variant: ToastVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contact = _contact;
    final myUid = context.read<SessionController>().account?.uid;
    final isMe = myUid == widget.uid;

    final name = contact?.name ?? widget.fallbackName ?? 'Student';
    final photo = contact?.photo ?? widget.fallbackPhoto;
    final presence = contact?.presence;
    final online = presence?.isOnline ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s5,
          Tokens.s4,
          Tokens.s5,
          Tokens.s5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChatAvatar(url: photo, fallback: name, size: 88, online: online),
            const SizedBox(height: Tokens.s4),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            if (contact?.isTutor ?? false)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'Tutor',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            const SizedBox(height: Tokens.s2),

            // Presence, which is the one thing on here that changes while it is
            // being looked at.
            if (!isMe)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (online) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: BlueprintPalette.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    !_loaded
                        ? 'Loading…'
                        : online
                            ? 'Online'
                            : lastSeenLabel(presence?.lastSeen),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: online ? FontWeight.w700 : FontWeight.w400,
                      color: online
                          ? BlueprintPalette.success
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),

            if (contact?.email != null) ...[
              const SizedBox(height: Tokens.s4),
              _DetailRow(icon: Icons.mail_outline_rounded, value: contact!.email!),
            ],

            if (_loaded && contact == null) ...[
              const SizedBox(height: Tokens.s4),
              Text(
                'This account is no longer available.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],

            const SizedBox(height: Tokens.s5),
            Row(
              children: [
                if (widget.allowMessage && !isMe && contact != null) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _opening ? null : _message,
                      icon: _opening
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chat_bubble_rounded, size: 17),
                      label: const Text('Message'),
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
