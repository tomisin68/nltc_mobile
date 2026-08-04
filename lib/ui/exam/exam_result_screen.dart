import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/attempt_repository.dart';
import '../../domain/models/exam_attempt.dart';
import '../../domain/models/exam_config.dart';
import '../../domain/models/question.dart';
import '../../domain/models/subject.dart';
import '../core/format.dart';
import '../core/state/activity_controller.dart';
import '../core/state/practice_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/score_ring.dart';
import '../practice/exam_setup_sheet.dart';
import 'exam_review_screen.dart';

/// Per-subject scores for a multi-subject paper.
///
/// Port of the web's `.results-subjects` block. A candidate who scored 280 needs
/// to know it was Chemistry that cost them, not just that it was 280.
class _SubjectBreakdown extends StatelessWidget {
  const _SubjectBreakdown({
    required this.config,
    required this.questions,
    required this.answers,
  });

  final ExamConfig config;
  final List<Question> questions;
  final Map<String, String> answers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'By subject',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Tokens.s3),
        for (final section in config.sectionList)
          Builder(
            builder: (context) {
              var correct = 0;
              var answered = 0;
              final end = section.end.clamp(0, questions.length);
              for (var i = section.start; i < end; i++) {
                final question = questions[i];
                final chosen = answers[question.id];
                if (chosen != null) answered++;
                if (question.isCorrect(chosen)) correct++;
              }
              final total = end - section.start;
              final percent = total == 0 ? 0 : (correct / total * 100).round();
              final decoration = Subjects.decorate([section.name]).first;

              return Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s3),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(decoration.icon, size: 15, color: decoration.color),
                        const SizedBox(width: Tokens.s2),
                        Expanded(
                          child: Text(
                            section.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '$percent%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: percent >= 50
                                ? BlueprintPalette.success
                                : scheme.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : correct / total,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHigh,
                        valueColor: AlwaysStoppedAnimation(decoration.color),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$correct correct · ${answered - correct} wrong · '
                        '${total - answered} skipped',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// The three topics this sitting went worst on, each a shortcut into practice.
///
/// Port of `getWeakestTopics` and the web's `.results-weak-topics` block,
/// including its rule that a topic needs at least two questions to count — one
/// wrong answer is noise, not a weakness, and sending a student off to revise a
/// whole topic on that basis would waste their evening.
class _WeakestTopics extends StatelessWidget {
  const _WeakestTopics({
    required this.questions,
    required this.answers,
    required this.config,
  });

  final List<Question> questions;
  final Map<String, String> answers;
  final ExamConfig config;

  static const _minimumQuestions = 2;
  static const _take = 3;

  List<({String topic, int percent})> _weakest() {
    final tally = <String, ({int correct, int total})>{};

    for (final question in questions) {
      final topic = (question.topic ?? '').trim();
      if (topic.isEmpty) continue;
      final current = tally[topic] ?? (correct: 0, total: 0);
      tally[topic] = (
        correct: current.correct +
            (question.isCorrect(answers[question.id]) ? 1 : 0),
        total: current.total + 1,
      );
    }

    final rows = [
      for (final entry in tally.entries)
        if (entry.value.total >= _minimumQuestions)
          (
            topic: entry.key,
            percent: (entry.value.correct / entry.value.total * 100).round(),
          ),
    ]..sort((a, b) => a.percent.compareTo(b.percent));

    return rows.take(_take).toList();
  }

  Future<void> _practise(BuildContext context, String topic) async {
    // Straight into a fresh sitting on that topic, the way tapping a weak topic
    // on the website pushes `/cbt?mode=topic&autostart=1`.
    final entry =
        context.read<PracticeController>().entryFor(config.subject);
    await showExamSetupSheet(
      context,
      entry,
      initialTopic: topic,
      subjectKey: config.subjectKey,
      exam: CbtExam.topic,
      topicMode: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weakest = _weakest();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 16, color: scheme.error),
                const SizedBox(width: 7),
                Text(
                  'Topics to work on',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.s3),
            if (weakest.isEmpty)
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 15,
                    color: BlueprintPalette.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'None — keep practising and improving!',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              Wrap(
                spacing: Tokens.s2,
                runSpacing: Tokens.s2,
                children: [
                  for (final row in weakest)
                    ActionChip(
                      avatar: Icon(
                        Icons.play_arrow_rounded,
                        size: 15,
                        color: row.percent >= 50
                            ? BlueprintPalette.success
                            : scheme.error,
                      ),
                      label: Text('${row.topic} · ${row.percent}%'),
                      onPressed: () => _practise(context, row.topic),
                    ),
                ],
              ),
              const SizedBox(height: Tokens.s3),
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 13,
                    color: BlueprintPalette.warning,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Tap a topic to jump straight into focused practice.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The score reveal.
///
/// Replaces the runner in the stack, so Back from here lands on the practice
/// list rather than re-entering a finished exam.
class ExamResultScreen extends StatefulWidget {
  const ExamResultScreen({
    super.key,
    required this.config,
    required this.questions,
    required this.answers,
    required this.result,
  });

  final ExamConfig config;
  final List<Question> questions;
  final Map<String, String> answers;
  final SubmitResult result;

  @override
  State<ExamResultScreen> createState() => _ExamResultScreenState();
}

class _ExamResultScreenState extends State<ExamResultScreen> {
  @override
  void initState() {
    super.initState();
    // The single point where a new attempt exists — refreshing history here
    // keeps the dashboard and activity tab current without either polling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ActivityController>().reload();
    });
  }

  ExamConfig get config => widget.config;
  SubmitResult get result => widget.result;
  ExamAttempt get attempt => result.attempt;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final score = attempt.score;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Your result'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: Tokens.s2),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Tokens.s5,
            Tokens.s6,
            Tokens.s5,
            Tokens.s10,
          ),
          children: [
            Center(
              child: ScoreRing(
                percent: score,
                size: 176,
                strokeWidth: 14,
                caption: ScoreRing.bandFor(score),
              ),
            ),
            const SizedBox(height: Tokens.s6),
            // A full UTME paper is reported the way JAMB reports it — out of 400,
            // with 200 as the line most courses ask for. A percentage would be a
            // number no candidate can compare to anything.
            if (config.scoresOutOf400) ...[
              Text(
                '${(score / 100 * 400).round()} / 400',
                style: text.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: score >= 50 ? BlueprintPalette.success : scheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Tokens.s1),
            ],
            Text(
              '${attempt.correct} of ${attempt.total} correct',
              style: text.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Tokens.s2),
            Text(
              '${config.isMultiSubject ? '${config.sectionList.length} subjects' : config.subject}'
              '${config.topic == null ? '' : ' · ${config.topic}'}'
              ' · ${config.exam}',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Tokens.s6),
            if (config.isMultiSubject) ...[
              _SubjectBreakdown(
                config: config,
                questions: widget.questions,
                answers: widget.answers,
              ),
              const SizedBox(height: Tokens.s5),
            ],
            _Breakdown(attempt: attempt),
            const SizedBox(height: Tokens.s5),
            _WeakestTopics(
              questions: widget.questions,
              answers: widget.answers,
              config: config,
            ),
            const SizedBox(height: Tokens.s5),
            _SyncNotice(result: result),
            const SizedBox(height: Tokens.s6),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ExamReviewScreen(
                    subject: config.subject,
                    questions: widget.questions,
                    answers: widget.answers,
                  ),
                ),
              ),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Review every question'),
            ),
            const SizedBox(height: Tokens.s3),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to practice'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.attempt});

  final ExamAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final wrong = attempt.answeredCount - attempt.correct;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s3,
          vertical: Tokens.s5,
        ),
        child: Row(
          children: [
            _BreakdownCell(
              value: '${attempt.correct}',
              label: 'Correct',
              color: BlueprintPalette.success,
            ),
            _BreakdownCell(
              value: '$wrong',
              label: 'Wrong',
              color: Theme.of(context).colorScheme.error,
            ),
            _BreakdownCell(
              value: '${attempt.skippedCount}',
              label: 'Skipped',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            _BreakdownCell(
              value: formatDuration(attempt.durationSeconds),
              label: 'Time',
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownCell extends StatelessWidget {
  const _BreakdownCell({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: text.titleLarge?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Tokens.s1),
          Text(
            label,
            style: text.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Says plainly whether the score has reached the server yet.
///
/// A pending attempt is not a failure — the score is already banked locally and
/// the queue will push it — so the tone stays reassuring rather than alarming.
class _SyncNotice extends StatelessWidget {
  const _SyncNotice({required this.result});

  final SubmitResult result;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final (icon, background, foreground, message) = switch (result
        .attempt.syncState) {
      SyncState.synced => (
          Icons.bolt,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          result.xpEarned == null
              ? 'Saved to your account.'
              : 'Saved — you earned ${result.xpEarned} XP'
                  '${result.newXp == null ? '.' : ', for ${result.newXp} total.'}',
        ),
      SyncState.failed => (
          Icons.error_outline,
          scheme.errorContainer,
          scheme.onErrorContainer,
          'Saved on this device, but the server would not accept it. Your '
              'score still counts in your history here.',
        ),
      SyncState.pending => (
          Icons.cloud_upload_outlined,
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
          'Saved on this device. Your XP lands as soon as you are back online.',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Tokens.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Text(
              message,
              style: text.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
