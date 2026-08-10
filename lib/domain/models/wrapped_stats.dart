import 'package:intl/intl.dart';

import 'exam_attempt.dart';
import 'exam_result.dart';

/// The `yyyy-MM` key a month is stored and compared under.
String monthKeyFor(DateTime month) => DateFormat('yyyy-MM').format(month);

/// One subject's share of a month.
class SubjectTally {
  const SubjectTally({
    required this.subject,
    required this.questions,
    required this.correct,
    required this.sittings,
  });

  final String subject;
  final int questions;
  final int correct;
  final int sittings;

  int get accuracy => questions == 0 ? 0 : (correct / questions * 100).round();
}

/// A month of studying, reduced to the handful of numbers worth showing off.
///
/// Built from the server's record of finished sittings rather than the local
/// attempts table, because a student who also sits tests on the website would
/// otherwise get a recap that quietly omits half their month. Time studied is
/// the exception — only the local rows carry a duration — so it is nullable and
/// simply left out when this device has nothing to contribute.
class WrappedStats {
  const WrappedStats({
    required this.month,
    required this.sittings,
    required this.questions,
    required this.correct,
    required this.activeDays,
    required this.subjects,
    required this.bestScore,
    required this.bestScoreSubject,
    required this.timeStudied,
    required this.streak,
    required this.xp,
  });

  /// The first day of the month this covers.
  final DateTime month;

  final int sittings;
  final int questions;
  final int correct;

  /// Distinct calendar days with at least one finished sitting.
  final int activeDays;

  /// Every subject touched, most questions first.
  final List<SubjectTally> subjects;

  final int bestScore;
  final String? bestScoreSubject;

  /// Null when no sitting from this month was taken on this device.
  final Duration? timeStudied;

  /// Carried from the profile, so these are current values rather than
  /// month-bounded ones — the card says so.
  final int streak;
  final int xp;

  String get monthKey => monthKeyFor(month);
  String get monthLabel => DateFormat('MMMM yyyy').format(month);
  String get shortMonthLabel => DateFormat('MMM yyyy').format(month);

  bool get isEmpty => sittings == 0;

  int get accuracy => questions == 0 ? 0 : (correct / questions * 100).round();

  SubjectTally? get topSubject => subjects.isEmpty ? null : subjects.first;

  /// The subject answered best, among those with enough questions for the
  /// number to mean anything. Four right out of four is not a strength.
  SubjectTally? get sharpestSubject {
    final eligible =
        subjects.where((s) => s.questions >= _minQuestionsForStrength).toList();
    if (eligible.isEmpty) return null;
    eligible.sort((a, b) => b.accuracy.compareTo(a.accuracy));
    return eligible.first;
  }

  static const _minQuestionsForStrength = 20;

  /// The Wrapped headline — one label for the whole month.
  ///
  /// Ordered so the rarer, more flattering descriptions win: showing up almost
  /// every day is a harder thing to do than being accurate once, and a student
  /// who did both should be told about the harder one.
  String get title {
    if (isEmpty) return 'The Quiet Month';
    if (activeDays >= 20) return 'The Regular';
    if (questions >= 500) return 'The Marathoner';
    if (accuracy >= 85 && questions >= 100) return 'The Sharpshooter';
    if (subjects.length >= 5) return 'The All-Rounder';
    final top = topSubject;
    if (top != null && top.questions >= 50) return 'The ${top.subject} Head';
    if (sittings >= 10) return 'The Grinder';
    return 'The Starter';
  }

  /// One line under the headline, saying what earned it.
  String get subtitle {
    if (isEmpty) return 'Nothing sat this month — the next one is open.';
    if (activeDays >= 20) return 'You showed up $activeDays days out of the month.';
    if (questions >= 500) return 'You answered $questions questions in one month.';
    if (accuracy >= 85 && questions >= 100) {
      return 'You got $accuracy% of everything you touched right.';
    }
    if (subjects.length >= 5) {
      return 'You practised ${subjects.length} different subjects.';
    }
    final top = topSubject;
    if (top != null && top.questions >= 50) {
      return '${top.questions} of your questions were ${top.subject}.';
    }
    if (sittings >= 10) return 'You sat $sittings tests this month.';
    return 'You got started — that is the hard part.';
  }

  /// Reduces a month's sittings to a recap.
  ///
  /// [results] and [attempts] are unfiltered; this picks out the ones belonging
  /// to [month] so callers never have to agree on what a month boundary is.
  factory WrappedStats.from({
    required DateTime month,
    required List<ExamResult> results,
    required List<ExamAttempt> attempts,
    required int streak,
    required int xp,
  }) {
    final first = DateTime(month.year, month.month);
    final next = DateTime(month.year, month.month + 1);

    bool inMonth(DateTime? at) =>
        at != null && !at.isBefore(first) && at.isBefore(next);

    final mine = results.where((r) => inMonth(r.submittedAt)).toList();

    var questions = 0;
    var correct = 0;
    var bestScore = 0;
    String? bestScoreSubject;
    final days = <String>{};
    final tallies = <String, ({int questions, int correct, int sittings})>{};

    for (final r in mine) {
      questions += r.total;
      correct += r.correct;

      final at = r.submittedAt!;
      days.add('${at.year}-${at.month}-${at.day}');

      // A three-question sitting scored 100% is not the month's best result,
      // it is a rounding artefact. Hold the headline number to a real test.
      if (r.total >= 10 && r.percent > bestScore) {
        bestScore = r.percent;
        bestScoreSubject = r.subject;
      }

      final prior = tallies[r.subject];
      tallies[r.subject] = (
        questions: (prior?.questions ?? 0) + r.total,
        correct: (prior?.correct ?? 0) + r.correct,
        sittings: (prior?.sittings ?? 0) + 1,
      );
    }

    final subjects = tallies.entries
        .map((e) => SubjectTally(
              subject: e.key,
              questions: e.value.questions,
              correct: e.value.correct,
              sittings: e.value.sittings,
            ))
        .toList()
      ..sort((a, b) => b.questions.compareTo(a.questions));

    final localSeconds = attempts
        .where((a) => inMonth(a.submittedAt))
        .fold<int>(0, (sum, a) => sum + a.durationSeconds);

    return WrappedStats(
      month: first,
      sittings: mine.length,
      questions: questions,
      correct: correct,
      activeDays: days.length,
      subjects: subjects,
      bestScore: bestScore,
      bestScoreSubject: bestScoreSubject,
      timeStudied:
          localSeconds == 0 ? null : Duration(seconds: localSeconds),
      streak: streak,
      xp: xp,
    );
  }

  /// A short "3h 20m" / "45m" for the card.
  static String formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }
}
