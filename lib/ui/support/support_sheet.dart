import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositories/support_repository.dart';
import '../../domain/models/support_thread.dart';
import '../core/format.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';

/// NLTC's real contact details, for a student who would rather call or email.
///
/// Kept in step with `SUPPORT_CONTACT` in `src/utils/support.js` — these are the
/// live numbers, not placeholders, so they are worth checking against the
/// website before either copy is edited.
const _supportEmail = 'nextleveltutorialcollege@gmail.com';
const _supportPhones = <({String display, String tel})>[
  (display: '0701 708 0467', tel: '+2347017080467'),
  (display: '0805 326 8648', tel: '+2348053268648'),
];

/// Opens the help desk.
///
/// A full-height modal sheet rather than the website's floating panel: on a
/// phone a docked panel would either cover the screen anyway or be too small to
/// type into, and a sheet gets the keyboard handling and the swipe-to-dismiss
/// for free.
Future<void> showSupportSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SupportSheet(),
    );

/// Which of the sheet's three faces is showing.
enum _SupportView {
  /// The student's past conversations.
  history,

  /// The form that opens a new one.
  compose,

  /// One conversation, with its composer.
  chat,
}

class SupportSheet extends StatefulWidget {
  const SupportSheet({super.key});

  @override
  State<SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<SupportSheet> {
  /// The new-request form and the in-chat composer keep separate drafts, so
  /// starting a chat does not inherit half a sentence from the other one.
  final _draft = TextEditingController();
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  SupportTopic? _topic;
  bool _sending = false;

  _SupportView _view = _SupportView.compose;
  String _activeId = '';

  /// The landing view is picked once per opening, not on every snapshot —
  /// otherwise solving a request would yank the student out of the chat they
  /// are still reading.
  bool _routed = false;

  /// Threads whose replies have already been marked read, so the receipt is not
  /// re-written on every rebuild of the stream.
  final _acknowledged = <String>{};

  @override
  void dispose() {
    _draft.dispose();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _uid => context.read<SessionController>().account?.uid ?? '';

  /// What the admin inbox lists this student under.
  ///
  /// [AppUser.displayName] already falls back through the name fields to the
  /// email; the Firebase account is only reached for when the profile document
  /// has not loaded yet, which on a locked account is a real possibility.
  String get _name {
    final session = context.read<SessionController>();
    return session.profile?.displayName ??
        session.account?.displayName ??
        session.account?.email ??
        'Student';
  }

  void _openThread(String id) {
    _composer.clear();
    setState(() {
      _activeId = id;
      _view = _SupportView.chat;
    });
  }

  void _startNewChat() {
    _draft.clear();
    setState(() {
      _activeId = '';
      _topic = null;
      _view = _SupportView.compose;
    });
  }

  /// The opening message — always a brand-new conversation.
  Future<void> _startThread() async {
    final body = _draft.text.trim();
    if (body.isEmpty || _sending) return;
    final topic = _topic;
    if (topic == null) {
      showToast('Tell us what your issue is about first.',
          variant: ToastVariant.error);
      return;
    }

    final session = context.read<SessionController>();
    final repository = context.read<SupportRepository>();

    setState(() => _sending = true);
    try {
      final id = await repository.startThread(
        uid: _uid,
        profile: session.profile,
        email: session.account?.email ?? session.profile?.email ?? '',
        name: _name,
        text: body,
        topic: topic,
      );
      _draft.clear();
      _topic = null;
      if (mounted) _openThread(id);
      _scrollToEnd();
    } catch (error) {
      _failed(error);
    }
    if (mounted) setState(() => _sending = false);
  }

  /// A follow-up inside a conversation that is already open.
  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending || _activeId.isEmpty) return;

    setState(() => _sending = true);
    try {
      await context.read<SupportRepository>().sendMessage(
            threadId: _activeId,
            uid: _uid,
            name: _name,
            text: body,
          );
      _composer.clear();
      _scrollToEnd();
    } catch (error) {
      _failed(error);
    }
    if (mounted) setState(() => _sending = false);
  }

  void _failed(Object error) {
    showToast(
      error is FirebaseException && error.code == 'permission-denied'
          // The same message the website shows, because it is the same cause:
          // the rules block that carries /supportThreads has to be deployed
          // before either surface can write one.
          ? 'Support is not enabled yet — deploy the updated Firestore rules.'
          : 'Could not send your message. Try again.',
      variant: ToastVariant.error,
    );
  }

  Future<void> _markSolved() async {
    if (_activeId.isEmpty) return;
    try {
      await context.read<SupportRepository>().markSolved(_activeId);
      showToast('Marked as solved. Start a new chat any time.',
          variant: ToastVariant.success);
    } catch (_) {
      showToast('Could not update this request.', variant: ToastVariant.error);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: Motion.base,
        curve: Motion.enter,
      );
    });
  }

  Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      showToast('No app on this phone can open that.',
          variant: ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uid = _uid;

    return Container(
      // Just short of the top, so the sheet still reads as a panel over the app
      // rather than as a screen the student has navigated to.
      height: MediaQuery.sizeOf(context).height * 0.92,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Tokens.rXl),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: uid.isEmpty
          ? const Center(child: Text('Sign in to reach support.'))
          : StreamBuilder<List<SupportThread>>(
              stream: context.read<SupportRepository>().watchThreads(uid),
              builder: (context, snapshot) {
                final threads = snapshot.data;
                if (threads == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Land in whatever is still waiting on somebody; if everything
                // is settled, offer a fresh form rather than a closed chat.
                if (!_routed) {
                  _routed = true;
                  final live = threads.where((t) => !t.isResolved).firstOrNull;
                  if (live != null) {
                    _activeId = live.id;
                    _view = _SupportView.chat;
                  }
                }

                final active = threads
                    .where((t) => t.id == _activeId)
                    .firstOrNull;
                final inChat = _view == _SupportView.chat && active != null;

                // Opening a chat is the same as reading its replies. Deferred
                // off the build: it is a Firestore write, and the snapshot it
                // causes would otherwise land mid-frame.
                if (inChat &&
                    active.unreadForStudent > 0 &&
                    _acknowledged.add(active.id)) {
                  final repository = context.read<SupportRepository>();
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => repository.markRead(active.id),
                  );
                }

                return Column(
                  children: [
                    _Header(
                      view: _view,
                      thread: inChat ? active : null,
                      threadCount: threads.length,
                      onBack: threads.isEmpty || _view == _SupportView.history
                          ? null
                          : () => setState(() => _view = _SupportView.history),
                      onNew: _view == _SupportView.history ? _startNewChat : null,
                      onSolved: _markSolved,
                    ),
                    Expanded(
                      child: switch (_view) {
                        _SupportView.history => _ThreadList(
                            threads: threads,
                            onOpen: _openThread,
                            onNew: _startNewChat,
                            scroll: _scroll,
                          ),
                        _SupportView.chat when inChat => _Conversation(
                            threadId: active.id,
                            resolved: active.isResolved,
                            onNew: _startNewChat,
                            scroll: _scroll,
                          ),
                        _ => _FirstContact(
                            firstName: _name.split(' ').first,
                            earlier: threads.length,
                            onHistory: () =>
                                setState(() => _view = _SupportView.history),
                            topic: _topic,
                            onTopic: (t) => setState(() => _topic = t),
                            composer: _draft,
                            sending: _sending,
                            onSend: _startThread,
                            onCall: (tel) =>
                                _launch(Uri(scheme: 'tel', path: tel)),
                            onEmail: () => _launch(
                                Uri(scheme: 'mailto', path: _supportEmail)),
                            scroll: _scroll,
                          ),
                      },
                    ),
                    // A solved chat is read-only: the next question opens a new
                    // one, which is what the closing note offers.
                    if (inChat && !active.isResolved)
                      _Composer(
                        controller: _composer,
                        sending: _sending,
                        onSend: _send,
                      ),
                  ],
                );
              },
            ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.view,
    required this.thread,
    required this.threadCount,
    required this.onBack,
    required this.onNew,
    required this.onSolved,
  });

  final _SupportView view;

  /// Non-null only while a conversation is on screen — it is what the status
  /// chips describe.
  final SupportThread? thread;

  final int threadCount;

  /// Null when there is nothing to go back to.
  final VoidCallback? onBack;

  /// Null outside the history list, which is the only place it belongs.
  final VoidCallback? onNew;

  final VoidCallback onSolved;

  @override
  Widget build(BuildContext context) {
    final resolved = thread?.isResolved ?? false;
    final onHistory = view == _SupportView.history;

    return Container(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s3, Tokens.s2, Tokens.s3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BlueprintPalette.b700, BlueprintPalette.b500],
        ),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Tokens.rXl),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: Material(
                  color: BlueprintPalette.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(Tokens.rSm),
                  child: InkWell(
                    onTap: onBack,
                    borderRadius: BorderRadius.circular(Tokens.rSm),
                    child: Icon(
                      onBack == null
                          ? Icons.headset_mic_rounded
                          : Icons.chevron_left_rounded,
                      size: onBack == null ? 18 : 22,
                      color: BlueprintPalette.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      onHistory ? 'Your chats' : 'NLTC Support',
                      style: GoogleFonts.fraunces(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: BlueprintPalette.white,
                      ),
                    ),
                    Text(
                      onHistory
                          ? '$threadCount conversation${threadCount == 1 ? '' : 's'}'
                          : 'We usually reply within a few hours',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: BlueprintPalette.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              if (onNew != null)
                TextButton.icon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label: const Text('New'),
                  style: TextButton.styleFrom(
                    foregroundColor: BlueprintPalette.b800,
                    backgroundColor: BlueprintPalette.white,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded,
                    color: BlueprintPalette.white),
                tooltip: 'Close',
              ),
            ],
          ),
          if (thread != null) ...[
            const SizedBox(height: Tokens.s2),
            Row(
              children: [
                _HeaderChip(
                  icon: resolved
                      ? Icons.check_circle_rounded
                      : Icons.pending_rounded,
                  label: resolved ? 'Solved' : 'Open',
                ),
                const SizedBox(width: Tokens.s2),
                Flexible(
                  child: _HeaderChip(
                    icon: Icons.sell_rounded,
                    label: SupportTopic.labelFor(thread!.topic),
                  ),
                ),
                const Spacer(),
                if (!resolved)
                  TextButton(
                    onPressed: onSolved,
                    style: TextButton.styleFrom(
                      foregroundColor: BlueprintPalette.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Mark solved',
                      style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: BlueprintPalette.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: BlueprintPalette.white),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: BlueprintPalette.white,
                ),
              ),
            ),
          ],
        ),
      );
}

// ─── First contact ───────────────────────────────────────────────────────────

/// The form that opens a conversation: pick a subject, say what happened, and —
/// for anyone who would rather not type it — the phone numbers.
///
/// Shown on a student's very first visit and again every time they come back
/// with nothing outstanding, which is what keeps one request per chat.
class _FirstContact extends StatelessWidget {
  const _FirstContact({
    required this.firstName,
    required this.earlier,
    required this.onHistory,
    required this.topic,
    required this.onTopic,
    required this.composer,
    required this.sending,
    required this.onSend,
    required this.onCall,
    required this.onEmail,
    required this.scroll,
  });

  final String firstName;

  /// How many conversations this student already has. Zero on a first visit.
  final int earlier;

  final VoidCallback onHistory;
  final SupportTopic? topic;
  final ValueChanged<SupportTopic> onTopic;
  final TextEditingController composer;
  final bool sending;
  final VoidCallback onSend;
  final ValueChanged<String> onCall;
  final VoidCallback onEmail;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final returning = earlier > 0;

    return ListView(
      controller: scroll,
      padding: EdgeInsets.fromLTRB(
        Tokens.s4,
        Tokens.s4,
        Tokens.s4,
        // Clears the keyboard when it is up, so the send button stays reachable.
        Tokens.s4 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        Text(
          returning ? 'Start a new chat' : 'Hi $firstName 👋',
          style: GoogleFonts.fraunces(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: Tokens.s2),
        Text(
          returning
              ? 'Every question gets its own chat, so nothing gets lost in an '
                  'old one. Tell us what this is about and an admin will reply '
                  'right here.'
              : 'Something not working, a payment not showing, or a question '
                  'about your classes? Send us a message here and an admin will '
                  'reply right in this window.',
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (returning) ...[
          const SizedBox(height: Tokens.s3),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onHistory,
              icon: const Icon(Icons.history_rounded, size: 15),
              label: Text('See your past chats ($earlier)'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
        const SizedBox(height: Tokens.s5),
        _Label('What is it about?'),
        const SizedBox(height: Tokens.s2),
        Wrap(
          spacing: Tokens.s2,
          runSpacing: Tokens.s2,
          children: [
            for (final option in SupportTopic.values)
              _TopicChip(
                topic: option,
                selected: topic == option,
                onTap: () => onTopic(option),
              ),
          ],
        ),
        const SizedBox(height: Tokens.s5),
        _Label('Tell us what happened'),
        const SizedBox(height: Tokens.s2),
        TextField(
          controller: composer,
          maxLines: 5,
          maxLength: SupportRepository.maxMessageLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText:
                'E.g. I paid my fee on Monday but my account still says expired…',
          ),
        ),
        const SizedBox(height: Tokens.s2),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, size: 16),
            label: Text(sending ? 'Sending…' : 'Send to support'),
          ),
        ),
        const SizedBox(height: Tokens.s6),
        Container(
          padding: const EdgeInsets.all(Tokens.s3),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(Tokens.rMd),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Prefer to call or email?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: Tokens.s2),
              Wrap(
                spacing: Tokens.s2,
                runSpacing: Tokens.s2,
                children: [
                  for (final phone in _supportPhones)
                    _ContactLink(
                      icon: Icons.call_rounded,
                      label: phone.display,
                      onTap: () => onCall(phone.tel),
                    ),
                  _ContactLink(
                    icon: Icons.mail_rounded,
                    label: _supportEmail,
                    onTap: onEmail,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({
    required this.topic,
    required this.selected,
    required this.onTap,
  });

  final SupportTopic topic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                topic.icon,
                size: 13,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                topic.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactLink extends StatelessWidget {
  const _ContactLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.rXs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── History ─────────────────────────────────────────────────────────────────

/// Every conversation this student has had with the desk, newest first.
///
/// Solved requests are not deleted and not reopened — they sit here so a
/// student can go back and read what they were told, which is most of the point
/// of giving each request its own chat.
class _ThreadList extends StatelessWidget {
  const _ThreadList({
    required this.threads,
    required this.onOpen,
    required this.onNew,
    required this.scroll,
  });

  final List<SupportThread> threads;
  final ValueChanged<String> onOpen;
  final VoidCallback onNew;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView.separated(
      controller: scroll,
      padding: const EdgeInsets.all(Tokens.s4),
      itemCount: threads.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: Tokens.s2),
      itemBuilder: (context, index) {
        if (index == 0) {
          return SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Start a new chat'),
            ),
          );
        }

        final thread = threads[index - 1];
        final done = thread.isResolved;

        return Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Tokens.rMd),
          child: InkWell(
            onTap: () => onOpen(thread.id),
            borderRadius: BorderRadius.circular(Tokens.rMd),
            child: Container(
              padding: const EdgeInsets.all(Tokens.s3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Tokens.rMd),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: done
                          ? BlueprintPalette.successBg
                          : scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(Tokens.rSm),
                    ),
                    child: Icon(
                      _iconFor(thread.topic),
                      size: 16,
                      color: done
                          ? BlueprintPalette.success
                          : scheme.onPrimaryContainer,
                    ),
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
                                SupportTopic.labelFor(thread.topic),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            if (thread.lastActivity != null)
                              Text(
                                relativeTime(thread.lastActivity!),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          thread.lastMessageFromAdmin
                              ? 'Support: ${thread.lastMessage ?? ''}'
                              : thread.lastMessage ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Tokens.s2),
                        Row(
                          children: [
                            _Pill(
                              label: done ? 'Solved' : 'Open',
                              background: done
                                  ? BlueprintPalette.successBg
                                  : scheme.primaryContainer,
                              foreground: done
                                  ? BlueprintPalette.success
                                  : scheme.onPrimaryContainer,
                            ),
                            if (thread.unreadForStudent > 0) ...[
                              const SizedBox(width: Tokens.s2),
                              _Pill(
                                label: '${thread.unreadForStudent} new',
                                background: BlueprintPalette.error,
                                foreground: BlueprintPalette.white,
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
      },
    );
  }

  static IconData _iconFor(String? id) {
    for (final topic in SupportTopic.values) {
      if (topic.id == id) return topic.icon;
    }
    return Icons.chat_bubble_rounded;
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: foreground,
          ),
        ),
      );
}

// ─── Conversation ────────────────────────────────────────────────────────────

class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.threadId,
    required this.resolved,
    required this.onNew,
    required this.scroll,
  });

  final String threadId;
  final bool resolved;

  /// A closed chat stays closed — this is the way out of it.
  final VoidCallback onNew;

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<SupportMessage>>(
      stream: context.read<SupportRepository>().watchMessages(threadId),
      builder: (context, snapshot) {
        final messages = snapshot.data;
        if (messages == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(
            Tokens.s4,
            Tokens.s4,
            Tokens.s4,
            Tokens.s2,
          ),
          itemCount: messages.length + (resolved ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == messages.length) {
              return Container(
                margin: const EdgeInsets.only(top: Tokens.s3),
                padding: const EdgeInsets.all(Tokens.s3),
                decoration: BoxDecoration(
                  color: BlueprintPalette.successBg,
                  borderRadius: BorderRadius.circular(Tokens.rSm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 15, color: BlueprintPalette.success),
                    const SizedBox(width: Tokens.s2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'This chat is closed. Need something else?',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: BlueprintPalette.text1,
                            ),
                          ),
                          TextButton(
                            onPressed: onNew,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Start a new chat',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            final message = messages[index];
            final previous = index == 0 ? null : messages[index - 1];
            final showDay = _dayLabel(message.createdAt) !=
                _dayLabel(previous?.createdAt);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDay && message.createdAt != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Tokens.s2),
                    child: Text(
                      _dayLabel(message.createdAt),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                _Bubble(message: message),
              ],
            );
          },
        );
      },
    );
  }

  static String _dayLabel(DateTime? at) {
    if (at == null) return '';
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    if (sameDay(at, today)) return 'Today';
    if (sameDay(at, yesterday)) return 'Yesterday';
    return DateFormat('d MMM y').format(at);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = !message.fromAdmin;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: Tokens.s2),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: mine ? scheme.primary : scheme.surfaceContainerHigh,
                // The corner nearest the speaker is squared off, so who said
                // what is readable without relying on colour alone.
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(Tokens.rMd),
                  topRight: const Radius.circular(Tokens.rMd),
                  bottomLeft: Radius.circular(mine ? Tokens.rMd : 3),
                  bottomRight: Radius.circular(mine ? 3 : Tokens.rMd),
                ),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: mine ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                [
                  if (message.fromAdmin) message.senderName ?? 'NLTC Support',
                  message.createdAt == null
                      ? 'Sending…'
                      : DateFormat('h:mm a').format(message.createdAt!),
                ].join(' · '),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Composer ────────────────────────────────────────────────────────────────

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(
        Tokens.s3,
        Tokens.s2,
        Tokens.s3,
        Tokens.s2 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              maxLength: SupportRepository.maxMessageLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Type your message…',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: Tokens.s2),
          IconButton.filled(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            tooltip: 'Send',
          ),
        ],
      ),
    );
  }
}
