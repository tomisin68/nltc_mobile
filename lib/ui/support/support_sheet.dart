import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositories/support_repository.dart';
import '../../domain/models/support_thread.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';

/// NLTC's real contact details, for a student who would rather call or email.
///
/// Kept in step with `SUPPORT_CONTACT` in `src/utils/support.js` — these are the
/// live numbers, not placeholders, so they are worth checking against the
/// website before either copy is edited.
const _supportEmail = 'nextleveltutorial@gmail.com';
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

class SupportSheet extends StatefulWidget {
  const SupportSheet({super.key});

  @override
  State<SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<SupportSheet> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  SupportTopic? _topic;
  bool _sending = false;

  /// Cleared once the student has read whatever was waiting, so the badge is not
  /// re-cleared on every rebuild of the stream.
  bool _acknowledged = false;

  @override
  void dispose() {
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

  Future<void> _send(SupportThread? thread) async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) return;
    if (thread == null && _topic == null) {
      showToast('Tell us what your issue is about first.',
          variant: ToastVariant.error);
      return;
    }

    final session = context.read<SessionController>();
    final repository = context.read<SupportRepository>();

    setState(() => _sending = true);
    try {
      await repository.sendMessage(
        uid: _uid,
        profile: session.profile,
        email: session.account?.email ?? session.profile?.email ?? '',
        name: _name,
        text: body,
        thread: thread,
        topic: _topic,
      );
      _composer.clear();
      _topic = null;
      _scrollToEnd();
    } on FirebaseException catch (error) {
      showToast(
        error.code == 'permission-denied'
            // The same message the website shows, because it is the same cause:
            // the rules block that carries /supportThreads has to be deployed
            // before either surface can write one.
            ? 'Support is not enabled yet — deploy the updated Firestore rules.'
            : 'Could not send your message. Try again.',
        variant: ToastVariant.error,
      );
    } catch (_) {
      showToast('Could not send your message. Try again.',
          variant: ToastVariant.error);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _markSolved() async {
    try {
      await context.read<SupportRepository>().markSolved(_uid);
      showToast('Marked as solved. Send a message any time to reopen it.',
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
          : StreamBuilder<SupportThread?>(
              stream: context.read<SupportRepository>().watchThread(uid),
              builder: (context, snapshot) {
                final thread = snapshot.data;
                final loading = snapshot.connectionState ==
                        ConnectionState.waiting &&
                    !snapshot.hasData;

                // Opening the panel is the same as reading the replies. Deferred
                // off the build: it is a Firestore write, and the snapshot it
                // causes would otherwise land mid-frame.
                if (!_acknowledged && (thread?.unreadForStudent ?? 0) > 0) {
                  _acknowledged = true;
                  final repository = context.read<SupportRepository>();
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => repository.markRead(uid),
                  );
                }

                return Column(
                  children: [
                    _Header(thread: thread, onSolved: _markSolved),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : thread == null
                              ? _FirstContact(
                                  firstName: _name.split(' ').first,
                                  topic: _topic,
                                  onTopic: (t) => setState(() => _topic = t),
                                  composer: _composer,
                                  sending: _sending,
                                  onSend: () => _send(null),
                                  onCall: (tel) =>
                                      _launch(Uri(scheme: 'tel', path: tel)),
                                  onEmail: () => _launch(
                                      Uri(scheme: 'mailto', path: _supportEmail)),
                                  scroll: _scroll,
                                )
                              : _Conversation(
                                  uid: uid,
                                  resolved: thread.isResolved,
                                  scroll: _scroll,
                                ),
                    ),
                    if (thread != null)
                      _Composer(
                        controller: _composer,
                        sending: _sending,
                        onSend: () => _send(thread),
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
  const _Header({required this.thread, required this.onSolved});

  final SupportThread? thread;
  final VoidCallback onSolved;

  @override
  Widget build(BuildContext context) {
    final resolved = thread?.isResolved ?? false;

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
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: BlueprintPalette.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(Tokens.rSm),
                ),
                child: const Icon(Icons.headset_mic_rounded,
                    size: 18, color: BlueprintPalette.white),
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'NLTC Support',
                      style: GoogleFonts.fraunces(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: BlueprintPalette.white,
                      ),
                    ),
                    Text(
                      'We usually reply within a few hours',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: BlueprintPalette.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
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

/// The form a student sees before they have a thread: pick a subject, say what
/// happened, and — for anyone who would rather not type it — the phone numbers.
class _FirstContact extends StatelessWidget {
  const _FirstContact({
    required this.firstName,
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
          'Hi $firstName 👋',
          style: GoogleFonts.fraunces(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: Tokens.s2),
        Text(
          'Something not working, a payment not showing, or a question about '
          'your classes? Send us a message here and an admin will reply right '
          'in this window.',
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: scheme.onSurfaceVariant,
          ),
        ),
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

// ─── Conversation ────────────────────────────────────────────────────────────

class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.uid,
    required this.resolved,
    required this.scroll,
  });

  final String uid;
  final bool resolved;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<SupportMessage>>(
      stream: context.read<SupportRepository>().watchMessages(uid),
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
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 15, color: BlueprintPalette.success),
                    SizedBox(width: Tokens.s2),
                    Expanded(
                      child: Text(
                        'This request is marked solved. Send another message '
                        'and it reopens straight away.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: BlueprintPalette.text1,
                        ),
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
