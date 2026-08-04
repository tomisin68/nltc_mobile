import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/mock_exam_repository.dart';
import '../../domain/models/access_state.dart';
import '../../domain/models/mock_exam.dart';
import '../core/format.dart';
import '../core/state/session_controller.dart';
import '../core/state/xp_service.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/filter_bar.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/skeleton.dart';
import 'mock_exam_runner.dart';

/// Mock Exams.
///
/// Port of `src/pages/dashboard/MockExamsView.jsx`. A submitted mock shows as
/// pending until a teacher publishes results; once published the score appears,
/// XP is credited exactly once, and the paper becomes reviewable. There are no
/// retakes — one attempt per exam, which is the rule the web enforces too.
class MockExamsScreen extends StatefulWidget {
  const MockExamsScreen({super.key});

  @override
  State<MockExamsScreen> createState() => _MockExamsScreenState();
}

class _MockExamsScreenState extends State<MockExamsScreen> {
  List<MockExam> _exams = const [];
  Map<String, MockSubmission> _submissions = const {};
  bool _loading = true;
  String? _error;

  String? _type;
  String? _department;

  /// Exams currently being credited, so a rebuild mid-award can't double-fire.
  final _awarding = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final repository = context.read<MockExamRepository>();
    final uid = context.read<SessionController>().account?.uid;

    try {
      final exams = await repository.published();
      final submissions =
          uid == null ? <String, MockSubmission>{} : await repository.submissions(exams, uid);
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _submissions = submissions;
        _loading = false;
      });
      _creditPublishedResults();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _exams = const [];
        _error = e is Exception ? e.toString() : 'unknown';
        _loading = false;
      });
    }
  }

  /// Credits XP for any submission whose results have just been published.
  ///
  /// Guarded twice, as on the web: an `xpAwarded` flag on the server document
  /// (idempotent across devices and visits) and an in-memory set (guards a
  /// double-fire within one screen).
  Future<void> _creditPublishedResults() async {
    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return;

    // Both read before the first await: this loop spans several round trips, and
    // reaching back into the tree afterwards is what `use_build_context_
    // synchronously` is warning about.
    final xp = context.read<XpService>();
    final repository = context.read<MockExamRepository>();

    for (final exam in _exams) {
      final submission = _submissions[exam.id];
      if (submission == null) continue;
      if (!exam.resultsPublished || submission.xpAwarded) continue;
      if (!_awarding.add(exam.id)) continue;

      final result = await xp.recordSession(
        subject: exam.title,
        exam: 'mock',
        score: submission.score,
        correct: submission.correct,
        total: submission.total == 0 ? 1 : submission.total,
      );

      if (result == null) {
        // Let the next visit retry rather than losing the award.
        _awarding.remove(exam.id);
        continue;
      }
      await repository.markXpAwarded(exam.id, uid);
    }
  }

  Future<void> _start(MockExam exam) async {
    final session = context.read<SessionController>();
    // Re-read on the tap: this list can sit on screen across the end of a trial.
    if (!AccessState.evaluate(session.profile).active) {
      showToast('Upgrade to Pro to access mock exams',
          variant: ToastVariant.info);
      return;
    }

    final submitted = await MockExamRunner.open(context, exam);
    // A finished sitting changes this exam's status, so reload rather than
    // leaving a Start button on an exam that has now been sat.
    if (submitted == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final access = context.select<SessionController, AccessState>(
      (s) => s.access,
    );

    final filtered = _exams.where((e) {
      if (_type != null && e.type != _type) return false;
      if (_department != null && e.department != _department) return false;
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s4,
          0,
          Tokens.s4,
          Tokens.s10,
        ),
        children: [
          const PageHeader(
            title: 'Mock Exams',
            subtitle: 'Full-length timed exams modeled after real papers. '
                'Results are published by your teacher.',
          ),
          if (access.reason == AccessReason.trial)
            _Notice(
              icon: Icons.card_giftcard_rounded,
              title: 'Free Trial Active',
              body: 'You have full access for ${access.trialDaysLeft} more '
                  'day${access.trialDaysLeft == 1 ? '' : 's'}. Pay your fee to '
                  'keep access after your trial ends.',
            )
          else if (!access.active)
            const _Notice(
              icon: Icons.lock_rounded,
              title: 'Pro Feature',
              body: 'Upgrade to Pro to access mock exams.',
            ),
          if (_exams.isNotEmpty)
            FilterBar(
              filters: [
                FilterDropdown<String>(
                  value: _type,
                  allLabel: 'All Types',
                  options: MockExam.typeLabels.keys.toList(),
                  labelOf: (t) => MockExam.typeLabels[t]!,
                  onChanged: (value) => setState(() => _type = value),
                ),
                FilterDropdown<String>(
                  value: _department,
                  allLabel: 'All Departments',
                  options: MockExam.departmentLabels.keys.toList(),
                  labelOf: (d) => MockExam.departmentLabels[d]!,
                  onChanged: (value) => setState(() => _department = value),
                ),
              ],
            ),
          if (_loading)
            AppCard(
              child: Column(
                children: [
                  for (var i = 0; i < 3; i++) const SkeletonListItem(lines: 2),
                ],
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s6),
              child: EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load mock exams',
                message: 'Check your internet connection and try again.',
                actionLabel: 'Retry',
                onAction: _load,
              ),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s6),
              child: EmptyState(
                icon: Icons.description_outlined,
                title: _exams.isEmpty
                    ? 'No mock exams available'
                    : 'No exams match your filter',
                message: _exams.isEmpty
                    ? 'Check back soon — new mock exams are added regularly.'
                    : 'Try changing the type or department filter.',
              ),
            )
          else
            for (final exam in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s3),
                child: _ExamCard(
                  exam: exam,
                  submission: _submissions[exam.id],
                  canStart: access.active,
                  onStart: () => _start(exam),
                  onReview: () => MockExamRunner.openReview(context, exam),
                ),
              ),
        ],
      ),
    );
  }
}

/// `.upgrade-banner` — the trial / locked notice above the list.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s4),
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: isDark ? scheme.surfaceContainerLow : BlueprintPalette.b50,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(Tokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({
    required this.exam,
    required this.submission,
    required this.canStart,
    required this.onStart,
    required this.onReview,
  });

  final MockExam exam;
  final MockSubmission? submission;
  final bool canStart;
  final VoidCallback onStart;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sat = submission != null;
    final resultVisible = sat && exam.resultsPublished;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.description_rounded, size: 26, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      exam.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        AppBadge(
                          label: exam.typeLabel,
                          tone: exam.type == 'jamb'
                              ? BadgeTone.navy
                              : BadgeTone.teal,
                        ),
                        if (exam.departmentLabel != null)
                          AppBadge(label: exam.departmentLabel!),
                        if (exam.totalDuration > 0)
                          AppBadge(
                            label: '${exam.totalDuration} min',
                            icon: Icons.schedule_rounded,
                          ),
                        AppBadge(label: '${exam.questionCount} questions'),
                      ],
                    ),
                    if (exam.subjectLine.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        exam.subjectLine,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (sat) ...[
            const SizedBox(height: 10),
            if (resultVisible)
              _Result(submission: submission!)
            else
              Row(
                children: [
                  Icon(
                    Icons.hourglass_bottom_rounded,
                    size: 14,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Submitted — results pending publication',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
          ],
          const SizedBox(height: Tokens.s3),
          SizedBox(
            width: double.infinity,
            child: sat && !resultVisible
                // Nothing to do until the teacher publishes.
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.hourglass_bottom_rounded, size: 16),
                    label: const Text('Pending'),
                  )
                : resultVisible
                    // Results are out, so there are no retakes — only review.
                    ? OutlinedButton.icon(
                        onPressed: onReview,
                        icon: const Icon(Icons.visibility_rounded, size: 16),
                        label: const Text('Review'),
                      )
                    : FilledButton.icon(
                        onPressed: canStart ? onStart : null,
                        icon: Icon(
                          canStart
                              ? Icons.play_arrow_rounded
                              : Icons.lock_rounded,
                          size: 17,
                        ),
                        label: Text(canStart ? 'Start' : 'Locked'),
                      ),
          ),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.submission});

  final MockSubmission submission;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final passed = submission.score >= 50;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${submission.score}%',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1,
                color: passed ? scheme.tertiary : scheme.error,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${submission.correct}/${submission.total} correct',
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (submission.subjectBreakdown.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (final s in submission.subjectBreakdown)
                Text(
                  '${s.subject}: ${s.correct}/${s.total}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
        if (submission.attempts.length > 1) ...[
          const SizedBox(height: 10),
          DashedRule(color: scheme.outlineVariant),
          const SizedBox(height: 8),
          Text(
            'ATTEMPT HISTORY (${submission.attempts.length})',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          for (var i = 0; i < submission.attempts.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      'Attempt ${i + 1}:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    '${submission.attempts[i].score}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: submission.attempts[i].score >= 50
                          ? scheme.tertiary
                          : scheme.error,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${submission.attempts[i].correct}/'
                      '${submission.attempts[i].total} correct',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    formatDate(submission.attempts[i].submittedAt),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
