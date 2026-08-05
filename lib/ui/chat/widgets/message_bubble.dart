import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/chat.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/in_app_browser.dart';
import '../chat_screen.dart' show ChatAvatar;
import 'link_preview_card.dart';
import 'message_attachment.dart';

/// One message, with everything that can hang off it.
///
/// Swipe-to-reply lives here rather than in the list so the drag only moves this
/// bubble — dragging the whole row, as a `Dismissible` would, reads as deleting
/// it. The threshold matches the website's 60px.
class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.chat,
    required this.myUid,
    required this.showSender,
    required this.showAvatar,
    required this.selectionMode,
    required this.selected,
    required this.highlighted,
    required this.onReply,
    required this.onLongPress,
    required this.onTapQuoted,
    required this.onToggleSelect,
    required this.onTapReaction,
    required this.onTapSender,
  });

  final ChatMessage message;
  final bool isMine;
  final Chat? chat;
  final String myUid;

  /// True for the first message of a run in a group — the name only needs
  /// saying once.
  final bool showSender;
  final bool showAvatar;

  final bool selectionMode;
  final bool selected;

  /// True while this message is flashing after being jumped to.
  final bool highlighted;

  final VoidCallback onReply;
  final VoidCallback onLongPress;

  /// Tapping the quoted block jumps to the message it quotes.
  final VoidCallback onTapQuoted;

  final VoidCallback onToggleSelect;
  final void Function(String emoji) onTapReaction;

  /// Tapping the avatar or the name above a message opens that person.
  final VoidCallback onTapSender;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  double _dragged = 0;

  /// Past this, releasing arms the reply. Same number the web uses.
  static const _replyThreshold = 60.0;
  static const _maxDrag = 80.0;

  void _onDragUpdate(DragUpdateDetails details) {
    // Rightward only: a left drag on a message means nothing, and letting it
    // move both ways makes the list feel loose.
    setState(
      () => _dragged = (_dragged + details.delta.dx).clamp(0.0, _maxDrag),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    final armed = _dragged > _replyThreshold;
    setState(() => _dragged = 0);
    if (armed) widget.onReply();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = widget.message;

    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              message.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onHorizontalDragUpdate: widget.selectionMode ? null : _onDragUpdate,
      onHorizontalDragEnd: widget.selectionMode ? null : _onDragEnd,
      onLongPress: widget.selectionMode ? null : widget.onLongPress,
      onTap: widget.selectionMode ? widget.onToggleSelect : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: widget.highlighted ? Motion.base : Duration.zero,
        color: widget.selected
            ? scheme.primary.withValues(alpha: 0.14)
            : widget.highlighted
                ? scheme.primary.withValues(alpha: 0.16)
                : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 3),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // The reply arrow revealed underneath as the bubble slides away.
            if (_dragged > 6)
              Opacity(
                opacity: (_dragged / _replyThreshold).clamp(0.0, 1.0),
                child: Icon(
                  Icons.reply_rounded,
                  size: 20,
                  color: _dragged > _replyThreshold
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              ),
            AnimatedContainer(
              duration: _dragged == 0 ? Motion.fast : Duration.zero,
              transform: Matrix4.translationValues(_dragged, 0, 0),
              child: Row(
                mainAxisAlignment:
                    widget.isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.selectionMode) ...[
                    Icon(
                      widget.selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 19,
                      color: widget.selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                  ],
                  if (!widget.isMine && widget.showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 2),
                      child: GestureDetector(
                        onTap: widget.selectionMode ? null : widget.onTapSender,
                        child: ChatAvatar(
                          url: message.senderPhoto,
                          fallback: message.senderName ?? 'Student',
                          size: 26,
                        ),
                      ),
                    )
                  else if (!widget.isMine && (widget.chat?.isGroup ?? false))
                    const SizedBox(width: 32),
                  Flexible(child: _bubble(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = widget.message;
    final isMine = widget.isMine;
    final foreground = isMine ? scheme.onPrimary : scheme.onSurface;

    return Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.76,
          ),
          padding: EdgeInsets.all(message.hasAttachment ? 5 : 0),
          decoration: BoxDecoration(
            color: isMine ? scheme.primary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(Tokens.rMd),
              topRight: const Radius.circular(Tokens.rMd),
              bottomLeft: Radius.circular(isMine ? Tokens.rMd : 4),
              bottomRight: Radius.circular(isMine ? 4 : Tokens.rMd),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showSender && !message.deleted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(7, 6, 7, 0),
                  child: GestureDetector(
                    onTap: widget.selectionMode ? null : widget.onTapSender,
                    child: Text(
                      (message.senderName ?? 'Someone').split(' ').first,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isMine ? scheme.onPrimary : scheme.primary,
                      ),
                    ),
                  ),
                ),

              if (message.replyTo != null && !message.deleted)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    message.hasAttachment ? 2 : 7,
                    5,
                    message.hasAttachment ? 2 : 7,
                    0,
                  ),
                  child: _QuotedBlock(
                    quoted: message.replyTo!,
                    isMine: isMine,
                    onTap: widget.onTapQuoted,
                  ),
                ),

              if (message.deleted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.block_rounded,
                        size: 13,
                        color: foreground.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'This message was deleted',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          color: foreground.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                if (message.hasAttachment)
                  MessageAttachment(message: message, isMine: isMine),
                if (message.uploadProgress != null) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: message.uploadProgress,
                      minHeight: 3,
                    ),
                  ),
                ],
                if (_captionOrText(message).isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      message.hasAttachment ? 4 : 11,
                      message.hasAttachment ? 6 : 8,
                      message.hasAttachment ? 4 : 11,
                      0,
                    ),
                    child: LinkifiedText(
                      text: _captionOrText(message),
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: foreground,
                      ),
                    ),
                  ),
                // What the link points at. Below the text rather than above it,
                // so the message a classmate actually typed is still the first
                // thing read. A picture or a document already is its own
                // preview, so a caption with a link in it doesn't get a second.
                if (!message.hasAttachment && _link(message) != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 7, right: 7),
                    child: LinkPreviewCard(
                      url: _link(message)!,
                      isMine: isMine,
                    ),
                  ),
              ],

              // Time and ticks, tucked to the trailing edge.
              if (!message.deleted)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    11,
                    3,
                    message.hasAttachment ? 5 : 11,
                    message.hasAttachment ? 3 : 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (message.sentAt != null)
                        Text(
                          DateFormat('HH:mm').format(message.sentAt!),
                          style: TextStyle(
                            fontSize: 9.5,
                            color: foreground.withValues(alpha: 0.7),
                          ),
                        ),
                      if (isMine) ...[
                        const SizedBox(width: 4),
                        _Ticks(
                          message: message,
                          chat: widget.chat,
                          myUid: widget.myUid,
                          onPrimary: scheme.onPrimary,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),

        if (message.reactions.isNotEmpty && !message.deleted)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              spacing: 4,
              children: [
                for (final entry in message.reactions.entries)
                  if (entry.value.isNotEmpty)
                    InkWell(
                      onTap: () => widget.onTapReaction(entry.key),
                      borderRadius: BorderRadius.circular(100),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: entry.value.contains(widget.myUid)
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Text(
                          '${entry.key} ${entry.value.length}',
                          style: const TextStyle(fontSize: 10.5),
                        ),
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }

  /// A caption belongs under its picture; a plain message is just its text.
  static String _captionOrText(ChatMessage message) {
    if (message.hasAttachment) return message.caption ?? '';
    return message.text;
  }

  /// The link this message is about, if it has one. Only the first: a message
  /// listing five links wants to stay a message, not become five cards.
  static String? _link(ChatMessage message) =>
      firstLinkIn(_captionOrText(message));
}

/// The quoted message above a reply. Tapping it jumps to the original.
class _QuotedBlock extends StatelessWidget {
  const _QuotedBlock({
    required this.quoted,
    required this.isMine,
    required this.onTap,
  });

  final QuotedMessage quoted;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = isMine ? scheme.onPrimary : scheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(
              color: isMine ? scheme.onPrimary : scheme.primary,
              width: 2.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (quoted.senderName ?? 'Someone').split(' ').first,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: foreground.withValues(alpha: 0.9),
              ),
            ),
            Text(
              quoted.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: foreground.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How far this message has got: a clock while it is being written, one tick on
/// the server, two grey ticks once it has reached everyone, two blue once they
/// have read it.
///
/// The second tick is a receipt the recipients' own devices wrote — see
/// [Chat.statusOf]. It used to be inferred from whether the other person looked
/// online, which is why it seemed to come and go for no reason.
class _Ticks extends StatelessWidget {
  const _Ticks({
    required this.message,
    required this.chat,
    required this.myUid,
    required this.onPrimary,
  });

  final ChatMessage message;
  final Chat? chat;
  final String myUid;
  final Color onPrimary;

  /// The blue the website uses. Hard-coded rather than themed because it has to
  /// stay legible on the navy bubble in both light and dark.
  static const _read = Color(0xFF53BDEB);

  @override
  Widget build(BuildContext context) {
    final status = chat?.statusOf(message, myUid) ??
        (message.pending ? MessageStatus.sending : MessageStatus.sent);
    final faded = onPrimary.withValues(alpha: 0.7);

    return switch (status) {
      MessageStatus.sending =>
        Icon(Icons.schedule_rounded, size: 11, color: faded),
      MessageStatus.sent =>
        Icon(Icons.check_rounded, size: 13, color: faded),
      MessageStatus.delivered =>
        Icon(Icons.done_all_rounded, size: 13, color: faded),
      MessageStatus.read =>
        const Icon(Icons.done_all_rounded, size: 13, color: _read),
    };
  }
}

/// The "Today" / "Yesterday" / date divider between runs of messages.
class DateSeparator extends StatelessWidget {
  const DateSeparator({super.key, required this.date});

  final DateTime date;

  static bool sameDay(DateTime? a, DateTime? b) =>
      a != null &&
      b != null &&
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;

  static String label(DateTime date) {
    final now = DateTime.now();
    if (sameDay(date, now)) return 'Today';
    if (sameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return DateFormat('d MMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            label(date),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
