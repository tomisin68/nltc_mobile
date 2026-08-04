import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/chat_repository.dart';
import '../../../domain/models/chat.dart';
import '../../core/theme/app_palette.dart';
import '../chat_screen.dart' show ChatAvatar;

/// A search box over everyone this student can message, and the results under it.
///
/// The one place the three pickers — new message, new group, add to group — get
/// their list from, because they had drifted into three slightly different
/// filters over three separately fetched copies of the same collection.
///
/// Searching is asked of the repository rather than done here: the cached
/// directory is capped, so a name that isn't in it has to be looked up on the
/// server, and only the repository knows whether that is necessary. Typing is
/// debounced so a fast typist causes one lookup rather than one per letter.
class ContactSearchList extends StatefulWidget {
  const ContactSearchList({
    super.key,
    required this.onTap,
    this.selected = const <String>{},
    this.exclude = const <String>{},
    this.multiSelect = false,
    this.autofocus = false,
    this.hintText = 'Search by name or email…',
  });

  final void Function(ChatContact contact) onTap;

  /// The uids currently ticked, when [multiSelect].
  final Set<String> selected;

  /// People to leave out — this student, and anyone already in the group.
  final Set<String> exclude;

  final bool multiSelect;
  final bool autofocus;
  final String hintText;

  @override
  State<ContactSearchList> createState() => _ContactSearchListState();
}

class _ContactSearchListState extends State<ContactSearchList> {
  static const _debounce = Duration(milliseconds: 350);

  final _field = TextEditingController();
  Timer? _debounceTimer;

  /// Guards against an earlier, slower search landing after a later one and
  /// putting stale results under a query the student has already moved on from.
  int _generation = 0;

  List<ChatContact>? _results;
  String _query = '';
  bool _searching = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value.trim());
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => _run(_query));
  }

  Future<void> _run(String query) async {
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final found =
          await context.read<ChatRepository>().searchContacts(query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = found;
        _searching = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = _results;
    final visible = results
        ?.where((c) => !widget.exclude.contains(c.uid))
        .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _field,
          autofocus: widget.autofocus,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            isDense: true,
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _field.clear();
                      _onChanged('');
                    },
                    icon: const Icon(Icons.close_rounded, size: 17),
                    tooltip: 'Clear',
                  ),
          ),
        ),
        // Sits under the field rather than replacing the list, so results already
        // on screen stay readable while a wider search runs behind them.
        SizedBox(
          height: 2,
          child: _searching
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: Tokens.s2),
        Flexible(
          child: switch ((visible, _error)) {
            (_, final Object _) => _Notice(
                icon: Icons.wifi_off_rounded,
                message: 'Could not load people. Check your connection.',
                actionLabel: 'Try again',
                onAction: () => _run(_query),
              ),
            (null, _) => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: Tokens.s6),
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            (final List<ChatContact> found, _) when found.isEmpty => _Notice(
                icon: Icons.person_search_rounded,
                message: _query.isEmpty
                    ? 'Nobody to message yet.'
                    : 'Nobody matches "$_query".',
              ),
            (final List<ChatContact> found, _) => ListView.builder(
                shrinkWrap: true,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: found.length,
                itemBuilder: (context, i) {
                  final contact = found[i];
                  final subtitle = contact.isTutor
                      ? 'Tutor'
                      : contact.email ?? '';

                  final avatar = ChatAvatar(
                    url: contact.photo,
                    fallback: contact.name,
                    size: widget.multiSelect ? 36 : 38,
                    online: contact.presence.isOnline,
                  );
                  final title = Text(
                    contact.name,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                  final caption = subtitle.isEmpty
                      ? null
                      : Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: contact.isTutor
                                ? FontWeight.w800
                                : FontWeight.w400,
                            color: contact.isTutor
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        );

                  if (!widget.multiSelect) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: avatar,
                      title: title,
                      subtitle: caption,
                      onTap: () => widget.onTap(contact),
                    );
                  }

                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: widget.selected.contains(contact.uid),
                    onChanged: (_) => widget.onTap(contact),
                    secondary: avatar,
                    title: title,
                    subtitle: caption,
                  );
                },
              ),
          },
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Tokens.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: scheme.onSurfaceVariant),
            const SizedBox(height: Tokens.s3),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Tokens.s2),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
