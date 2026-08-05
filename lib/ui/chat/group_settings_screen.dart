import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/chat_repository.dart';
import '../../data/services/api_client.dart' show ApiException;
import '../../domain/models/chat.dart';
import '../core/state/presence_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/photo_viewer.dart';
import 'chat_screen.dart' show ChatAvatar;
import 'user_profile_sheet.dart';
import 'widgets/contact_search_list.dart';

/// Group info and administration.
///
/// Port of the web's group-settings drawer: photo, name and description, the
/// announcement-only lock, the member list with add/remove/promote, and leaving.
/// Everything but leaving is admin-only, and the rules enforce that server-side
/// too — this only decides what is worth showing.
class GroupSettingsScreen extends StatefulWidget {
  const GroupSettingsScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  StreamSubscription<Chat?>? _subscription;
  Chat? _chat;

  final _name = TextEditingController();
  final _description = TextEditingController();

  /// Held rather than looked up in `dispose` — see the note on the chat list.
  PresenceController? _presence;

  bool _hydrated = false;
  bool _saving = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _subscription =
        context.read<ChatRepository>().watchChat(widget.chatId).listen((chat) {
      if (!mounted) return;
      setState(() {
        _chat = chat;
        // Only the first time: the stream fires on every edit, and refilling
        // would yank the text out from under someone mid-rename.
        if (!_hydrated && chat != null) {
          _hydrated = true;
          _name.text = chat.name ?? '';
          _description.text = chat.description ?? '';
        }
      });
    });
  }

  @override
  void dispose() {
    _presence?.untrack('group-${widget.chatId}');
    _subscription?.cancel();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  String? get _myUid => context.read<SessionController>().account?.uid;
  bool get _isAdmin => _chat?.isAdmin(_myUid) ?? false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<ChatRepository>().saveGroupInfo(
            widget.chatId,
            name: _name.text.trim().isEmpty
                ? (_chat?.name ?? 'Group')
                : _name.text,
            description: _description.text,
          );
      if (mounted) {
        showToast('Group updated.', variant: ToastVariant.success);
      }
    } catch (_) {
      if (mounted) {
        showToast('Could not save the group.', variant: ToastVariant.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      await context
          .read<ChatRepository>()
          .uploadGroupPhoto(widget.chatId, File(picked.path));
    } catch (_) {
      if (mounted) {
        showToast('Photo upload failed.', variant: ToastVariant.error);
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _toggleLock() async {
    final chat = _chat;
    final uid = _myUid;
    if (chat == null || uid == null) return;
    try {
      await context
          .read<ChatRepository>()
          .setGroupLocked(widget.chatId, !chat.locked, uid);
    } catch (_) {
      if (mounted) {
        showToast('Could not change that.', variant: ToastVariant.error);
      }
    }
  }

  Future<void> _addMembers() async {
    final chat = _chat;
    final session = context.read<SessionController>();
    if (chat == null) return;

    final chats = context.read<ChatRepository>();

    final picked = await showModalBottomSheet<List<ChatContact>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MemberPicker(exclude: chat.members.toSet()),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    try {
      await chats.addMembers(
        widget.chatId,
        chat: chat,
        contacts: picked,
        byName: session.profile?.displayName ?? 'Someone',
      );
    } catch (error) {
      if (mounted) {
        showToast(
          error is ApiException ? error.message : 'Could not add them.',
          variant: ToastVariant.error,
        );
      }
    }
  }

  Future<void> _removeMember(String uid, String name) async {
    final chat = _chat;
    if (chat == null) return;

    final confirmed = await _confirm(
      title: 'Remove $name?',
      message: 'They will stop receiving messages from this group.',
      action: 'Remove',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    try {
      await context
          .read<ChatRepository>()
          .removeMember(widget.chatId, chat: chat, uid: uid);
    } catch (error) {
      if (mounted) {
        showToast(
          error is ApiException ? error.message : 'Could not remove them.',
          variant: ToastVariant.error,
        );
      }
    }
  }

  Future<void> _addAdmin(String uid, String name) async {
    final chat = _chat;
    if (chat == null) return;

    final confirmed = await _confirm(
      title: 'Make $name an admin?',
      message: 'They will be able to rename the group, add and remove members, '
          'lock it, and make other people admins. You stay an admin too.',
      action: 'Make admin',
    );
    if (confirmed != true || !mounted) return;

    try {
      await context
          .read<ChatRepository>()
          .addAdmin(widget.chatId, chat: chat, uid: uid);
    } catch (_) {
      if (mounted) {
        showToast('Could not update the admins.', variant: ToastVariant.error);
      }
    }
  }

  Future<void> _dismissAdmin(String uid, String name) async {
    final chat = _chat;
    if (chat == null) return;

    final isMe = uid == _myUid;
    final confirmed = await _confirm(
      title: isMe ? 'Step down as admin?' : 'Dismiss $name as admin?',
      message: isMe
          ? 'You will stay in the group, but you will no longer be able to '
              'manage it.'
          : 'They will stay in the group, but will no longer be able to manage '
              'it.',
      action: isMe ? 'Step down' : 'Dismiss',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    try {
      await context
          .read<ChatRepository>()
          .removeAdmin(widget.chatId, chat: chat, uid: uid);
    } catch (error) {
      if (mounted) {
        showToast(
          error is ApiException
              ? error.message
              : 'Could not update the admins.',
          variant: ToastVariant.error,
        );
      }
    }
  }

  Future<void> _leave() async {
    final chat = _chat;
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (chat == null || uid == null) return;

    final confirmed = await _confirm(
      title: 'Leave this group?',
      message: 'You will stop receiving messages from it.',
      action: 'Leave',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final chats = context.read<ChatRepository>();
    final navigator = Navigator.of(context);
    try {
      await chats.leaveGroup(
        widget.chatId,
        chat: chat,
        uid: uid,
        name: session.profile?.displayName ?? 'Someone',
      );
      if (!mounted) return;
      // Out of the settings and out of the conversation — there is nothing left
      // here to come back to.
      navigator
        ..pop()
        ..pop();
    } catch (error) {
      if (mounted) {
        showToast(
          error is ApiException
              ? error.message
              : 'Could not leave the group.',
          variant: ToastVariant.error,
        );
      }
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor:
                          Theme.of(dialogContext).colorScheme.error,
                    )
                  : null,
              child: Text(action),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chat = _chat;
    final myUid = _myUid;

    final presence = context.watch<PresenceController>();
    _presence = presence;
    presence.track(
      'group-${widget.chatId}',
      chat?.members ?? const <String>[],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Group info')),
      body: chat == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Tokens.s4,
                Tokens.s4,
                Tokens.s4,
                Tokens.s10,
              ),
              children: [
                Center(
                  child: Stack(
                    children: [
                      ChatAvatar(
                        url: chat.groupPhoto,
                        fallback: chat.name ?? 'Group',
                        isGroup: true,
                        size: 96,
                        // Viewing the picture is the tap; changing it is the
                        // camera button in the corner, admins only.
                        onTap: () => PhotoViewer.open(
                          context,
                          chat.groupPhoto,
                          title: chat.name,
                        ),
                      ),
                      if (_uploadingPhoto)
                        const Positioned.fill(
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          ),
                        ),
                      if (_isAdmin)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Material(
                            color: scheme.primary,
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: _uploadingPhoto ? null : _changePhoto,
                              customBorder: const CircleBorder(),
                              child: Padding(
                                padding: const EdgeInsets.all(7),
                                child: Icon(
                                  Icons.photo_camera_rounded,
                                  size: 15,
                                  color: scheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Tokens.s5),

                if (_isAdmin) ...[
                  AppCard(
                    title: 'Group details',
                    titleIcon: Icons.edit_rounded,
                    child: Column(
                      children: [
                        TextField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Group name',
                            isDense: true,
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: Tokens.s4),
                        TextField(
                          controller: _description,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            isDense: true,
                          ),
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: Tokens.s4),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded, size: 17),
                            label: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Tokens.s4),
                  AppCard(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: chat.locked,
                      onChanged: (_) => _toggleLock(),
                      title: const Text(
                        'Announcements only',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Only admins can post. Everyone else can read.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Tokens.s4),
                ] else ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chat.name ?? 'Group',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (chat.description?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 4),
                          Text(
                            chat.description!,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (chat.locked) ...[
                          const SizedBox(height: Tokens.s3),
                          Row(
                            children: [
                              Icon(
                                Icons.campaign_rounded,
                                size: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Announcements only — only admins post.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: Tokens.s4),
                ],

                AppCard(
                  title: '${chat.members.length} members',
                  titleIcon: Icons.group_rounded,
                  padding: EdgeInsets.zero,
                  headerTrailing: _isAdmin
                      ? CardAction(
                          label: 'Add',
                          icon: Icons.person_add_rounded,
                          onTap: _addMembers,
                        )
                      : null,
                  child: Column(
                    children: [
                      // Admins first, then everybody else: who runs the group is
                      // the thing a member most often opens this list to find.
                      for (final member in [
                        ...chat.admins,
                        ...chat.members.where((m) => !chat.isAdmin(m)),
                      ])
                        _MemberRow(
                          name: member == myUid
                              ? 'You'
                              : chat.memberNames[member] ?? 'Student',
                          photo: chat.memberPhotos[member],
                          online: presence.isOnline(member),
                          isAdmin: chat.isAdmin(member),
                          // Any admin can manage anyone. Themselves too — the
                          // only self-management on offer is stepping down,
                          // because leaving is its own button below.
                          canManage: _isAdmin,
                          isMe: member == myUid,
                          onOpen: member == myUid
                              ? null
                              : () => showUserProfile(
                                    context,
                                    uid: member,
                                    fallbackName: chat.memberNames[member],
                                    fallbackPhoto: chat.memberPhotos[member],
                                  ),
                          onRemove: () => _removeMember(
                            member,
                            chat.memberNames[member] ?? 'this member',
                          ),
                          onAddAdmin: () => _addAdmin(
                            member,
                            chat.memberNames[member] ?? 'this member',
                          ),
                          onDismissAdmin: () => _dismissAdmin(
                            member,
                            chat.memberNames[member] ?? 'this member',
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Tokens.s5),

                OutlinedButton.icon(
                  onPressed: _leave,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  label: const Text('Leave group'),
                ),
              ],
            ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.name,
    required this.photo,
    required this.online,
    required this.isAdmin,
    required this.canManage,
    required this.isMe,
    required this.onOpen,
    required this.onRemove,
    required this.onAddAdmin,
    required this.onDismissAdmin,
  });

  final String name;
  final String? photo;
  final bool online;
  final bool isAdmin;

  /// True when whoever is looking at this list may administer the group.
  final bool canManage;

  final bool isMe;

  /// Opens this member's profile. Null for the student's own row.
  final VoidCallback? onOpen;

  final VoidCallback onRemove;
  final VoidCallback onAddAdmin;
  final VoidCallback onDismissAdmin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
      leading:
          ChatAvatar(url: photo, fallback: name, size: 38, online: online),
      title: Text(
        name,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      subtitle: isAdmin
          ? Text(
              'Group admin',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            )
          : null,
      onTap: onOpen,
      trailing: canManage
          ? PopupMenuButton<String>(
              onSelected: (choice) => switch (choice) {
                'admin' => onAddAdmin(),
                'dismiss' => onDismissAdmin(),
                _ => onRemove(),
              },
              itemBuilder: (_) => [
                if (!isAdmin)
                  const PopupMenuItem(
                    value: 'admin',
                    child: Text('Make group admin'),
                  ),
                if (isAdmin)
                  PopupMenuItem(
                    value: 'dismiss',
                    child: Text(
                      isMe ? 'Step down as admin' : 'Dismiss as admin',
                    ),
                  ),
                // Removing yourself is what the Leave button is for.
                if (!isMe)
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove from group'),
                  ),
              ],
            )
          : null,
    );
  }
}

/// Multi-select picker for adding people to a group.
class _MemberPicker extends StatefulWidget {
  const _MemberPicker({required this.exclude});

  /// Everyone already in the group.
  final Set<String> exclude;

  @override
  State<_MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<_MemberPicker> {
  final _picked = <ChatContact>[];

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
              'Add members${_picked.isEmpty ? '' : ' (${_picked.length})'}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: Tokens.s3),
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
              child: FilledButton(
                onPressed: _picked.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_picked),
                child: Text(
                  _picked.isEmpty
                      ? 'Select people to add'
                      : 'Add ${_picked.length}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
