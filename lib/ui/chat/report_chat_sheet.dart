import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/chat_repository.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';

/// Reasons a student can pick from, plus room to explain.
///
/// A fixed list rather than a free-text box alone: it tells the student what
/// this platform considers reportable, and it gives whoever reviews the queue
/// something to sort by when several arrive at once.
const _reasons = <String>[
  'Bullying or harassment',
  'Threats or violence',
  'Sexual or inappropriate content',
  'Spam or scam',
  'Impersonation',
  'Something else',
];

/// Reports a conversation to the admins, with its full history attached.
///
/// The history is copied server-side, not from here: the app can only read
/// what the rules allow it to, and either party can soft-delete a message the
/// moment they realise a report has been filed. `POST /api/reports/chat` takes
/// the snapshot with the Admin SDK, past both problems.
Future<void> showReportChatSheet(
  BuildContext context, {
  required String chatId,
  required String chatTitle,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReportChatSheet(chatId: chatId, chatTitle: chatTitle),
    );

class _ReportChatSheet extends StatefulWidget {
  const _ReportChatSheet({required this.chatId, required this.chatTitle});

  final String chatId;
  final String chatTitle;

  @override
  State<_ReportChatSheet> createState() => _ReportChatSheetState();
}

class _ReportChatSheetState extends State<_ReportChatSheet> {
  String? _reason;
  final _details = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _sending) return;

    setState(() => _sending = true);
    try {
      await context.read<ChatRepository>().reportChat(
            chatId: widget.chatId,
            reason: reason,
            details: _details.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast('Report sent. Our team will review this conversation.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showToast('Could not send that report. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(Tokens.s4, Tokens.s5, Tokens.s4, insets + Tokens.s5),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report ${widget.chatTitle}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: Tokens.s2),
            Text(
              'A copy of this conversation is sent to our team so they can look '
              'into it. Nobody in the chat is told that you reported it.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Tokens.s4),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (v) {
                if (!_sending) setState(() => _reason = v);
              },
              child: Column(
                children: [
                  for (final reason in _reasons)
                    RadioListTile<String>(
                      value: reason,
                      title: Text(reason, style: const TextStyle(fontSize: 13.5)),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: Tokens.s3),
            TextField(
              controller: _details,
              enabled: !_sending,
              maxLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Anything else we should know? (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Tokens.s3),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _reason == null || _sending ? null : _submit,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
