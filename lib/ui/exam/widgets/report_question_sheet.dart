import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/question_report_repository.dart';
import '../../../domain/models/question.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/app_palette.dart';
import '../../core/toast.dart';

/// Reporting a suspect question, from wherever a question is on screen.
///
/// The website carries this on the exam hall and on the corrections screen for
/// the same reason both are wired up here: a student sitting the paper can only
/// doubt the wording, but one going through their corrections has just been
/// shown the answer key and is the person most likely to notice it is wrong.
///
/// Deliberately named "Report a problem" rather than "Flag": this app already
/// has a flag, and it means bookmark-for-later. Two flags on one screen would
/// be one too many.
class ReportQuestionButton extends StatefulWidget {
  const ReportQuestionButton({
    super.key,
    required this.question,
    required this.subject,
    this.examMode = 'practice',
    this.stage = 'exam',
    this.bank,
    this.dense = false,
  });

  final Question question;

  /// The subject as the student sees it, for the admin's triage badges.
  final String subject;

  /// How the sitting was recorded — `'jamb'`, `'bece'`, `'mock'`, `'practice'`.
  final String examMode;

  /// `'exam'` from the hall, `'review'` from the corrections.
  final String stage;

  /// Which collection the question came from. Worked out from [examMode] when
  /// the caller does not know.
  final String? bank;

  /// Smaller type and a one-word label, for sharing a row with the question
  /// number and its Correct/Wrong badge rather than living in the runner's own
  /// action row. A phone at 360dp has no space for the full label there.
  final bool dense;

  @override
  State<ReportQuestionButton> createState() => _ReportQuestionButtonState();
}

class _ReportQuestionButtonState extends State<ReportQuestionButton> {
  bool _reported = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The repository remembers the whole session, so a question reported during
    // the paper is already "Reported" by the time it is reviewed.
    final reported =
        _reported || context.read<QuestionReportRepository>().hasReported(widget.question.id);

    return TextButton.icon(
      onPressed: reported ? null : () => _open(context),
      icon: Icon(
        reported ? Icons.flag : Icons.outlined_flag,
        size: widget.dense ? 16 : 18,
      ),
      label: Text(
        reported
            ? 'Reported'
            : widget.dense
                ? 'Report'
                : 'Report a problem',
      ),
      style: TextButton.styleFrom(
        foregroundColor: reported ? scheme.error : scheme.onSurfaceVariant,
        disabledForegroundColor: scheme.error,
        textStyle: widget.dense ? Theme.of(context).textTheme.labelMedium : null,
        padding: widget.dense
            ? const EdgeInsets.symmetric(horizontal: Tokens.s2)
            : null,
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final filed = await showReportQuestionSheet(
      context,
      question: widget.question,
      subject: widget.subject,
      examMode: widget.examMode,
      stage: widget.stage,
      bank: widget.bank,
    );
    if (filed && mounted) setState(() => _reported = true);
  }
}

/// Opens the report form. Resolves true once a report has been filed.
Future<bool> showReportQuestionSheet(
  BuildContext context, {
  required Question question,
  required String subject,
  String examMode = 'practice',
  String stage = 'exam',
  String? bank,
}) async {
  final filed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReportQuestionSheet(
      question: question,
      subject: subject,
      examMode: examMode,
      stage: stage,
      bank: bank,
    ),
  );
  return filed ?? false;
}

class _ReportQuestionSheet extends StatefulWidget {
  const _ReportQuestionSheet({
    required this.question,
    required this.subject,
    required this.examMode,
    required this.stage,
    required this.bank,
  });

  final Question question;
  final String subject;
  final String examMode;
  final String stage;
  final String? bank;

  @override
  State<_ReportQuestionSheet> createState() => _ReportQuestionSheetState();
}

class _ReportQuestionSheetState extends State<_ReportQuestionSheet> {
  final _note = TextEditingController();

  String _reason = QuestionReportRepository.reasons.first;
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;

    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null) {
      showToast('Sign in to report a question.', variant: ToastVariant.error);
      return;
    }

    final repository = context.read<QuestionReportRepository>();
    final navigator = Navigator.of(context);

    setState(() => _sending = true);
    try {
      await repository.report(
        uid: uid,
        name: session.profile?.displayName ??
            session.account?.displayName ??
            session.account?.email ??
            'Student',
        email: session.account?.email ?? session.profile?.email ?? '',
        question: widget.question,
        subject: widget.subject,
        reason: _reason,
        note: _note.text,
        examMode: widget.examMode,
        stage: widget.stage,
        bank: widget.bank,
      );
      navigator.pop(true);
      showToast('Thanks — a tutor will check this question',
          variant: ToastVariant.success);
    } on FirebaseException catch (error) {
      showToast(
        error.code == 'permission-denied'
            // Same cause and same wording as the website: the rules block that
            // carries /flaggedQuestions has to be deployed before either
            // surface can file one.
            ? 'Reporting is not available yet — please tell your tutor.'
            : 'Could not send your report. Check your connection.',
        variant: ToastVariant.error,
      );
      if (mounted) setState(() => _sending = false);
    } catch (_) {
      showToast('Could not send your report. Check your connection.',
          variant: ToastVariant.error);
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        // Lifts the note field clear of the keyboard.
        padding: EdgeInsets.only(
          left: Tokens.s5,
          right: Tokens.s5,
          top: Tokens.s5,
          bottom: Tokens.s5 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.outlined_flag, size: 20, color: scheme.error),
                  const SizedBox(width: Tokens.s2),
                  Expanded(
                    child: Text('Report this question', style: text.titleMedium),
                  ),
                  IconButton(
                    onPressed: _sending ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: Tokens.s2),
              Text(
                widget.stage == 'review'
                    ? 'Your score is not affected — a tutor checks the question '
                        'and fixes it for everyone.'
                    : 'Your exam is not affected — the question stays on your '
                        'paper and a tutor checks it afterwards.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Tokens.s5),
              Text('What looks wrong?', style: text.titleSmall),
              const SizedBox(height: Tokens.s2),
              for (final reason in QuestionReportRepository.reasons)
                _ReasonRow(
                  label: reason,
                  selected: _reason == reason,
                  onTap: _sending ? null : () => setState(() => _reason = reason),
                ),
              const SizedBox(height: Tokens.s4),
              Text('Anything else? (optional)', style: text.titleSmall),
              const SizedBox(height: Tokens.s2),
              TextField(
                controller: _note,
                maxLines: 3,
                maxLength: QuestionReportRepository.maxNoteLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. options C and D are the same',
                  counterText: '',
                ),
              ),
              const SizedBox(height: Tokens.s4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(_sending ? 'Sending…' : 'Send report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One reason, hand-rolled rather than a RadioListTile so the row reads at the
/// sheet's own scale and picks up the app's tap target sizing.
class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.rSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Tokens.s2),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
