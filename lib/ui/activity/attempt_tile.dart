import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/question_repository.dart';
import '../../domain/models/exam_attempt.dart';
import '../core/format.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/score_ring.dart';
import '../exam/exam_review_screen.dart';

/// One row in the attempt history. Shared by the dashboard and the activity tab.
class AttemptTile extends StatelessWidget {
  const AttemptTile({super.key, required this.attempt, this.onTap});

  final ExamAttempt attempt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final score = attempt.score;
    final color = ScoreRing.colorFor(score, scheme);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => openAttemptReview(context, attempt),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s4),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${score.round()}%',
                  style: text.labelLarge?.copyWith(color: color, fontSize: 13),
                ),
              ),
              const SizedBox(width: Tokens.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attempt.subject.isEmpty ? 'Practice' : attempt.subject,
                      style: text.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${attempt.correct}/${attempt.total} correct · '
                      '${relativeTime(attempt.submittedAt)}',
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (attempt.syncState != SyncState.synced)
                Tooltip(
                  message: attempt.syncState == SyncState.pending
                      ? 'Waiting to sync'
                      : 'Could not be synced',
                  child: Icon(
                    attempt.syncState == SyncState.pending
                        ? Icons.cloud_upload_outlined
                        : Icons.cloud_off_outlined,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rebuilds a past sitting from the questions still on the device.
///
/// The pack the attempt was drawn from can be deleted between the sitting and
/// the review, which is the one case where a history row genuinely can't be
/// opened — so it says exactly that rather than showing a blank list.
Future<void> openAttemptReview(BuildContext context, ExamAttempt attempt) async {
  final questions = await context
      .read<QuestionRepository>()
      .questionsForReview(attempt.questionIds);

  if (!context.mounted) return;

  if (questions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'These questions are no longer on this device. Download '
          '${attempt.subject} again to review this sitting.',
        ),
      ),
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ExamReviewScreen(
        subject: attempt.subject,
        questions: questions,
        answers: attempt.answers,
      ),
    ),
  );
}
