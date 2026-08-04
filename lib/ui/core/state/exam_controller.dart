import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/attempt_repository.dart';
import '../../../domain/models/exam_config.dart';
import '../../../domain/models/question.dart';

/// How a single question stands, for the palette grid.
enum QuestionStatus { unanswered, answered, flagged }

/// Runs one sitting from the first question to the graded result.
///
/// Owns the clock, the answer sheet and the submission. Nothing here talks to
/// the network directly — [AttemptRepository] decides when the attempt leaves
/// the device, which is why a sitting finished in a basement still scores.
class ExamController extends ChangeNotifier {
  ExamController({
    required this.config,
    required this.questions,
    required AttemptRepository attempts,
    this.submitter,
  })  : _attempts = attempts,
        _remaining = config.duration ?? Duration.zero,
        _startedAt = DateTime.now() {
    if (config.isTimed) _startTicker();
  }

  final ExamConfig config;
  final List<Question> questions;
  final AttemptRepository _attempts;

  /// Replaces the default "grade and sync" submission.
  ///
  /// A mock exam is submitted to its own Firestore document and its score is
  /// withheld until a teacher publishes results, so it cannot go through
  /// [AttemptRepository] — that path records a sitting and claims XP immediately.
  /// Everything else about the sitting is identical, which is why this is a hook
  /// rather than a second controller.
  final Future<SubmitResult> Function(
    List<Question> questions,
    Map<String, String> answers,
    int durationSeconds,
  )? submitter;

  /// The answers as they stand. Exposed for a [submitter] that needs to record
  /// exactly what was chosen.
  Map<String, String> get answers => Map.unmodifiable(_answers);

  final Map<String, String> _answers = {};
  final Set<String> _flagged = {};

  Timer? _ticker;
  Duration _remaining;
  final DateTime _startedAt;

  int _index = 0;
  bool _submitting = false;
  SubmitResult? _result;
  String? _submitError;

  int get index => _index;
  int get total => questions.length;

  Duration get remaining => _remaining;
  bool get isSubmitting => _submitting;
  SubmitResult? get result => _result;
  String? get submitError => _submitError;

  int get answeredCount => _answers.length;
  int get flaggedCount => _flagged.length;
  int get unansweredCount => total - _answers.length;
  double get progress => total == 0 ? 0 : _answers.length / total;

  bool get isFirst => _index == 0;
  bool get isLast => _index >= total - 1;

  // ─── Sections ──────────────────────────────────────────────────────────────
  // A JAMB paper is four subjects end to end in one flat question list; a
  // single-subject sitting is a paper of one. Everything below reads the same
  // either way, so no caller has to branch on it.

  /// Every subject in this paper, in order.
  ///
  /// Clamped to the questions actually drawn: a section whose bank came back
  /// short would otherwise claim indices the paper doesn't have.
  List<ExamSection> get sections {
    final declared = config.sectionList;
    return [
      for (final s in declared)
        if (s.start < total)
          ExamSection(
            key: s.key,
            name: s.name,
            start: s.start,
            length: s.length.clamp(0, total - s.start),
          ),
    ];
  }

  /// The subject the question at [index] belongs to.
  ExamSection sectionAt(int index) => sections.firstWhere(
        (s) => s.contains(index),
        // Falls back to the last section rather than throwing: an off-by-one in
        // a section table must not take a student's exam down mid-sitting.
        orElse: () => sections.isEmpty
            ? ExamSection(key: config.subject, name: config.subject, start: 0, length: total)
            : sections.last,
      );

  ExamSection get currentSection => sectionAt(_index);

  /// Which subject is showing, as a position in [sections].
  int get currentSectionIndex {
    final all = sections;
    for (var i = 0; i < all.length; i++) {
      if (all[i].contains(_index)) return i;
    }
    return 0;
  }

  int answeredIn(ExamSection section) {
    var count = 0;
    for (var i = section.start; i < section.end && i < total; i++) {
      if (_answers.containsKey(questions[i].id)) count++;
    }
    return count;
  }

  int correctIn(ExamSection section) {
    var count = 0;
    for (var i = section.start; i < section.end && i < total; i++) {
      final q = questions[i];
      if (q.isCorrect(_answers[q.id])) count++;
    }
    return count;
  }

  /// Jumps to the first question of a subject — what tapping a subject pill does.
  void goToSection(ExamSection section) => goTo(section.start);

  /// True once the clock is inside the last five minutes — the point where the
  /// timer changes colour and stops being background furniture.
  bool get isRunningOut =>
      config.isTimed && _remaining <= const Duration(minutes: 5);

  bool get isCritical =>
      config.isTimed && _remaining <= const Duration(minutes: 1);

  String? answerFor(Question q) => _answers[q.id];
  bool isFlagged(Question q) => _flagged.contains(q.id);

  QuestionStatus statusAt(int i) {
    final q = questions[i];
    if (_flagged.contains(q.id)) return QuestionStatus.flagged;
    return _answers.containsKey(q.id)
        ? QuestionStatus.answered
        : QuestionStatus.unanswered;
  }

  String get formattedRemaining {
    final seconds = _remaining.inSeconds.clamp(0, 359999);
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// How long the sitting has actually taken, wall-clock. Used for the attempt
  /// record, so a paused-and-resumed exam still reports honest elapsed time.
  int get elapsedSeconds => DateTime.now().difference(_startedAt).inSeconds;

  // ─── Answering ─────────────────────────────────────────────────────────────

  // The question is passed in rather than read from [index]: a PageView builds
  // its neighbours, so a tap landing mid-swipe must act on the tile that was
  // actually pressed, not on whichever page the index has reached.

  void select(Question question, String optionKey) {
    if (_result != null) return;
    // In practice mode the reveal is the point of the answer — locking it stops
    // a student from clicking through all four to find the green one.
    if (config.revealsAnswers && _answers.containsKey(question.id)) return;

    _answers[question.id] = optionKey;
    notifyListeners();
  }

  void clearAnswer(Question question) {
    if (_answers.remove(question.id) != null) notifyListeners();
  }

  void toggleFlag(Question question) {
    if (!_flagged.remove(question.id)) _flagged.add(question.id);
    notifyListeners();
  }

  void goTo(int i) {
    if (i < 0 || i >= total || i == _index) return;
    _index = i;
    notifyListeners();
  }

  void next() => goTo(_index + 1);
  void previous() => goTo(_index - 1);

  // ─── Clock ─────────────────────────────────────────────────────────────────

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _remaining - const Duration(seconds: 1);
      _remaining = left.isNegative ? Duration.zero : left;
      notifyListeners();
      // Time up is a submission, not a discard — the student keeps every mark
      // they earned before the bell.
      if (_remaining == Duration.zero) unawaited(submit());
    });
  }

  // ─── Submission ────────────────────────────────────────────────────────────

  Future<SubmitResult?> submit() async {
    if (_submitting || _result != null) return _result;

    _ticker?.cancel();
    _ticker = null;
    _submitting = true;
    _submitError = null;
    notifyListeners();

    try {
      final result = await (submitter?.call(
            questions,
            Map.of(_answers),
            elapsedSeconds,
          ) ??
          _attempts.submit(
            subject: config.subject,
            exam: config.exam,
            topic: config.topic,
            questions: questions,
            answers: Map.of(_answers),
            durationSeconds: elapsedSeconds,
          ));
      _result = result;
      return result;
    } catch (e) {
      // Grading is local, so reaching here means the *save* failed — a full
      // disk, essentially. Say so rather than pretending the score is gone.
      _submitError = 'Could not save your attempt. Please try again.';
      if (config.isTimed && _remaining > Duration.zero) _startTicker();
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
