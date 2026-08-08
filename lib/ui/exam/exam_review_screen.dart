import 'package:flutter/material.dart';

import '../../domain/models/question.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/question_body.dart';
import 'widgets/option_tile.dart';
import 'widgets/report_question_sheet.dart';

/// Question-by-question review of a finished sitting.
///
/// Opened from the result screen and from the activity history. History review
/// depends on the questions still being on the device — deleting a subject pack
/// removes them — which is why the empty case here explains itself.
class ExamReviewScreen extends StatefulWidget {
  const ExamReviewScreen({
    super.key,
    required this.subject,
    required this.questions,
    required this.answers,
    this.examMode = 'practice',
  });

  final String subject;
  final List<Question> questions;

  /// questionId → chosen option key. A missing entry means it was skipped.
  final Map<String, String> answers;

  /// How the sitting was recorded — `'jamb'`, `'bece'`, `'mock'`. Rides along on
  /// a reported question so the admin knows which paper it came off.
  final String examMode;

  @override
  State<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

enum _ReviewFilter { all, wrong, skipped }

class _ExamReviewScreenState extends State<ExamReviewScreen> {
  _ReviewFilter _filter = _ReviewFilter.all;

  bool _matches(Question q) => switch (_filter) {
        _ReviewFilter.all => true,
        _ReviewFilter.wrong =>
          widget.answers.containsKey(q.id) && !q.isCorrect(widget.answers[q.id]),
        _ReviewFilter.skipped => !widget.answers.containsKey(q.id),
      };

  @override
  Widget build(BuildContext context) {
    // Numbers stay tied to the original order, so "question 7" means the same
    // thing whichever filter is on.
    final numbered = <(int, Question)>[
      for (final (i, q) in widget.questions.indexed)
        if (_matches(q)) (i + 1, q),
    ];

    final wrongCount = widget.questions
        .where((q) =>
            widget.answers.containsKey(q.id) && !q.isCorrect(widget.answers[q.id]))
        .length;
    final skippedCount =
        widget.questions.where((q) => !widget.answers.containsKey(q.id)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              0,
              Tokens.s4,
              Tokens.s3,
            ),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterChip(
                    label: 'All ${widget.questions.length}',
                    selected: _filter == _ReviewFilter.all,
                    onSelected: () => setState(() => _filter = _ReviewFilter.all),
                  ),
                  const SizedBox(width: Tokens.s2),
                  _FilterChip(
                    label: 'Wrong $wrongCount',
                    selected: _filter == _ReviewFilter.wrong,
                    onSelected: () =>
                        setState(() => _filter = _ReviewFilter.wrong),
                  ),
                  const SizedBox(width: Tokens.s2),
                  _FilterChip(
                    label: 'Skipped $skippedCount',
                    selected: _filter == _ReviewFilter.skipped,
                    onSelected: () =>
                        setState(() => _filter = _ReviewFilter.skipped),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: numbered.isEmpty
            ? EmptyState(
                icon: Icons.celebration_outlined,
                title: _filter == _ReviewFilter.wrong
                    ? 'Nothing wrong here'
                    : 'Nothing skipped',
                message: _filter == _ReviewFilter.wrong
                    ? 'You did not get a single question wrong in this sitting.'
                    : 'You answered every question in this sitting.',
                actionLabel: 'Show all questions',
                onAction: () => setState(() => _filter = _ReviewFilter.all),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.s5,
                  Tokens.s4,
                  Tokens.s5,
                  Tokens.s10,
                ),
                itemCount: numbered.length,
                separatorBuilder: (_, _) => const SizedBox(height: Tokens.s5),
                itemBuilder: (context, i) {
                  final (number, question) = numbered[i];
                  return _ReviewCard(
                    number: number,
                    question: question,
                    chosen: widget.answers[question.id],
                    subject: widget.subject,
                    examMode: widget.examMode,
                  );
                },
              ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.number,
    required this.question,
    required this.chosen,
    required this.subject,
    required this.examMode,
  });

  final int number;
  final Question question;
  final String? chosen;
  final String subject;
  final String examMode;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final skipped = chosen == null;
    final correct = question.isCorrect(chosen);

    final (badgeColor, badgeText) = switch (true) {
      _ when skipped => (scheme.onSurfaceVariant, 'Skipped'),
      _ when correct => (BlueprintPalette.success, 'Correct'),
      _ => (scheme.error, 'Wrong'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Question $number', style: text.titleSmall),
            const SizedBox(width: Tokens.s3),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.s2,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Tokens.rXs),
              ),
              child: Text(
                badgeText,
                style: text.labelSmall?.copyWith(
                  color: badgeColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            // Corrections are where a bad answer key gets caught — this is the
            // first time the student sees the key at all — so the report button
            // belongs here as much as it does in the exam hall.
            ReportQuestionButton(
              question: question,
              subject: question.subject.isNotEmpty ? question.subject : subject,
              examMode: examMode,
              stage: 'review',
              dense: true,
            ),
          ],
        ),
        const SizedBox(height: Tokens.s3),
        // Same markup the exam hall rendered — a correction that shows
        // `H<sub>2</sub>O` where the paper showed H₂O reads as a different
        // question.
        RichQuestionText(
          html: question.text,
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          selectable: true,
        ),
        const SizedBox(height: Tokens.s4),
        for (final key in Question.optionKeys)
          if (question.options[key] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s2),
              child: OptionTile(
                optionKey: key,
                label: question.options[key]!,
                selected: chosen == key,
                correct: key == question.answerKey,
              ),
            ),
        if (question.explanation != null && question.explanation!.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: Tokens.s2),
            padding: const EdgeInsets.all(Tokens.s4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(Tokens.rMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Tokens.s2),
                    Text('Why', style: text.titleSmall),
                  ],
                ),
                const SizedBox(height: Tokens.s2),
                RichQuestionText(
                  html: question.explanation!,
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
