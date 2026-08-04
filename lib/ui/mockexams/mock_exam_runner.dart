import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/attempt_repository.dart';
import '../../data/repositories/mock_exam_repository.dart';
import '../../domain/models/exam_attempt.dart';
import '../../domain/models/exam_config.dart';
import '../../domain/models/mock_exam.dart';
import '../../domain/models/question.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/app_card.dart';
import '../exam/exam_screen.dart';
import '../exam/exam_review_screen.dart';

/// Runs a mock exam.
///
/// Reuses the CBT runner wholesale — same clock, palette, answer sheet — with two
/// mock-specific differences, both taken from `CBTPage.jsx`'s mock branch: the
/// paper is drawn across several subjects to the counts the exam specifies, and
/// submission goes to the exam's own document instead of the attempt history, so
/// no score is shown until a teacher publishes results.
abstract final class MockExamRunner {
  /// Loads the paper and starts the sitting.
  ///
  /// Returns true once a sitting has been submitted, so the caller can refresh.
  static Future<bool?> open(BuildContext context, MockExam exam) async {
    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return null;

    final questions = await _loadPaper(context, exam);
    if (!context.mounted) return null;

    if (questions.isEmpty) {
      showToast(
        'This mock exam has no questions in the bank yet. Tell your tutor.',
        variant: ToastVariant.error,
      );
      return null;
    }

    final repository = context.read<MockExamRepository>();

    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ExamScreen(
          config: ExamConfig(
            // The attempt is filed under the exam's own title rather than a
            // subject — a mock spans several.
            subject: exam.title,
            exam: 'mock',
            questionCount: questions.length,
            mode: ExamMode.exam,
            duration: exam.totalDuration > 0
                ? Duration(minutes: exam.totalDuration)
                : ExamConfig.defaultDuration(questions.length),
          ),
          questions: questions,
          submitter: (served, answers, seconds) => _submit(
            repository: repository,
            exam: exam,
            uid: uid,
            questions: served,
            answers: answers,
            durationSeconds: seconds,
          ),
          onSubmitted: (screenContext, _) =>
              Navigator.of(screenContext).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => _PendingScreen(exam: exam),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens a published paper for review — the exact questions served, with what
  /// the student chose against the right answers.
  static Future<void> openReview(BuildContext context, MockExam exam) async {
    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('mockExams')
        .doc(exam.id)
        .collection('submissions')
        .doc(uid)
        .get();
    if (!context.mounted) return;

    final data = snap.data();
    final ids = ((data?['questionIds'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    final answers = <String, String>{
      for (final entry in ((data?['answers'] as Map?) ?? const {}).entries)
        entry.key.toString(): entry.value.toString(),
    };

    if (ids.isEmpty) {
      showToast(
        'This attempt was recorded before question review was available.',
        variant: ToastVariant.info,
      );
      return;
    }

    // Read the served questions back by id so review shows the paper that was
    // actually sat, not a fresh draw from the bank.
    final questions = await _questionsByIds(ids);
    if (!context.mounted) return;

    if (questions.isEmpty) {
      showToast('Could not load this paper for review.',
          variant: ToastVariant.error);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExamReviewScreen(
          subject: exam.title,
          questions: questions,
          answers: answers,
        ),
      ),
    );
  }

  /// Draws the paper: each subject's questions, to the count the exam asks for.
  static Future<List<Question>> _loadPaper(
    BuildContext context,
    MockExam exam,
  ) async {
    final db = FirebaseFirestore.instance;
    final paper = <Question>[];

    for (final spec in exam.subjects) {
      try {
        // Over-fetch then shuffle: Firestore cannot order randomly, and taking
        // the first N would serve the same paper to everyone.
        final snap = await db
            .collection('questions')
            .where('subject', isEqualTo: spec.subject)
            .limit(spec.count * 4)
            .get();
        final pool = snap.docs
            .map((d) => Question.fromMap(d.id, d.data()))
            .where((q) => q.isUsable)
            .toList()
          ..shuffle();
        paper.addAll(pool.take(spec.count));
      } catch (_) {
        // A subject that can't be read is skipped rather than failing the whole
        // paper — a three-of-four-subject mock still beats none.
      }
    }
    // Subjects stay grouped, the way a real paper is printed.
    return paper;
  }

  static Future<List<Question>> _questionsByIds(List<String> ids) async {
    final db = FirebaseFirestore.instance;
    final found = <String, Question>{};

    // `whereIn` caps at 30 ids per query.
    for (var i = 0; i < ids.length; i += 30) {
      final batch = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      try {
        final snap = await db
            .collection('questions')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in snap.docs) {
          found[doc.id] = Question.fromMap(doc.id, doc.data());
        }
      } catch (_) {
        // Skip an unreadable batch; the rest of the paper still reviews.
      }
    }
    // Restored in the order they were served.
    return [
      for (final id in ids)
        if (found[id] != null) found[id]!,
    ];
  }

  /// Writes the sitting to the exam's own document.
  ///
  /// Returns a [SubmitResult] because that is what the runner expects, but the
  /// score inside it is never shown — the pending screen replaces the results
  /// screen. The grade is computed anyway, since the teacher's results view reads
  /// it from this document.
  static Future<SubmitResult> _submit({
    required MockExamRepository repository,
    required MockExam exam,
    required String uid,
    required List<Question> questions,
    required Map<String, String> answers,
    required int durationSeconds,
  }) async {
    final attempt = ExamAttempt.grade(
      id: AttemptRepository.newAttemptId(),
      subject: exam.title,
      exam: 'mock',
      questions: questions,
      answers: answers,
      durationSeconds: durationSeconds,
    );

    // Per-subject marks, in the order the exam lists its subjects.
    final breakdown = <SubjectScore>[];
    for (final spec in exam.subjects) {
      final forSubject =
          questions.where((q) => q.subject == spec.subject).toList();
      if (forSubject.isEmpty) continue;
      final correct = forSubject
          .where((q) => answers[q.id] == q.answerKey)
          .length;
      breakdown.add(
        SubjectScore(
          subject: spec.subject,
          correct: correct,
          total: forSubject.length,
        ),
      );
    }

    await repository.saveSubmission(
      examId: exam.id,
      uid: uid,
      score: attempt.score.round(),
      correct: attempt.correct,
      total: questions.length,
      subjectBreakdown: breakdown,
      answers: answers,
      questionIds: questions.map((q) => q.id).toList(),
    );

    return SubmitResult(attempt: attempt);
  }
}

/// What a student sees straight after submitting a mock.
///
/// Port of the mock pending screen in `CBTPage.jsx`. No score, deliberately: the
/// teacher decides when marks are released.
class _PendingScreen extends StatelessWidget {
  const _PendingScreen({required this.exam});

  final MockExam exam;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Tokens.s5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.s6,
                  vertical: Tokens.s10,
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primaryContainer,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.hourglass_top_rounded,
                        size: 30,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: Tokens.s5),
                    Text(
                      'Exam Submitted',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.fraunces(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your answers for ${exam.title} have been recorded. '
                      'Your teacher will publish the results — you will see your '
                      'score here once they do.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.7,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Tokens.s6),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        // Pops all the way out of the exam, answering `true` to
                        // the list so it reloads with this exam marked pending.
                        onPressed: () =>
                            Navigator.of(context).pop<bool>(true),
                        child: const Text('Back to Mock Exams'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
