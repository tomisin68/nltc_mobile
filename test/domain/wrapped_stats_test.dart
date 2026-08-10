import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/exam_attempt.dart';
import 'package:nltc/domain/models/exam_result.dart';
import 'package:nltc/domain/models/wrapped_stats.dart';

ExamResult result({
  required String subject,
  required int correct,
  required int total,
  required DateTime at,
}) =>
    ExamResult(
      id: '$subject-${at.millisecondsSinceEpoch}',
      subject: subject,
      correct: correct,
      total: total,
      submittedAt: at,
    );

ExamAttempt attempt({required DateTime at, required int seconds}) => ExamAttempt(
      id: 'a-${at.millisecondsSinceEpoch}',
      subject: 'Physics',
      exam: 'jamb',
      questionIds: const [],
      answers: const {},
      correct: 1,
      total: 1,
      durationSeconds: seconds,
      submittedAt: at,
    );

WrappedStats build({
  List<ExamResult> results = const [],
  List<ExamAttempt> attempts = const [],
  int streak = 0,
  int xp = 0,
}) =>
    WrappedStats.from(
      month: DateTime(2026, 7),
      results: results,
      attempts: attempts,
      streak: streak,
      xp: xp,
    );

void main() {
  group('month boundaries', () {
    test('counts only sittings inside the month', () {
      final stats = build(results: [
        result(subject: 'Physics', correct: 8, total: 10, at: DateTime(2026, 7, 1)),
        result(subject: 'Physics', correct: 6, total: 10, at: DateTime(2026, 7, 31, 23, 59)),
        // Either side of the boundary — neither should be counted.
        result(subject: 'Physics', correct: 10, total: 10, at: DateTime(2026, 6, 30, 23, 59)),
        result(subject: 'Physics', correct: 10, total: 10, at: DateTime(2026, 8, 1)),
      ]);

      expect(stats.sittings, 2);
      expect(stats.questions, 20);
      expect(stats.correct, 14);
      expect(stats.accuracy, 70);
    });

    test('a sitting with no timestamp is ignored rather than counted', () {
      final stats = build(results: [
        const ExamResult(id: 'x', subject: 'Physics', correct: 9, total: 10),
      ]);

      expect(stats.isEmpty, isTrue);
      expect(stats.questions, 0);
    });
  });

  group('active days', () {
    test('several sittings on one day count as one day', () {
      final stats = build(results: [
        result(subject: 'Physics', correct: 5, total: 10, at: DateTime(2026, 7, 4, 9)),
        result(subject: 'Physics', correct: 5, total: 10, at: DateTime(2026, 7, 4, 18)),
        result(subject: 'Physics', correct: 5, total: 10, at: DateTime(2026, 7, 5, 9)),
      ]);

      expect(stats.sittings, 3);
      expect(stats.activeDays, 2);
    });
  });

  group('best score', () {
    test('ignores short sittings, which are a rounding artefact not a result', () {
      final stats = build(results: [
        // 100%, but off four questions — must not become the headline.
        result(subject: 'Physics', correct: 4, total: 4, at: DateTime(2026, 7, 2)),
        result(subject: 'Chemistry', correct: 17, total: 20, at: DateTime(2026, 7, 3)),
      ]);

      expect(stats.bestScore, 85);
      expect(stats.bestScoreSubject, 'Chemistry');
    });

    test('is zero when no sitting was long enough to qualify', () {
      final stats = build(results: [
        result(subject: 'Physics', correct: 3, total: 5, at: DateTime(2026, 7, 2)),
      ]);

      expect(stats.bestScore, 0);
      expect(stats.bestScoreSubject, isNull);
    });
  });

  group('subjects', () {
    test('ranks by questions answered, not by sittings', () {
      final stats = build(results: [
        result(subject: 'Maths', correct: 30, total: 40, at: DateTime(2026, 7, 2)),
        result(subject: 'English', correct: 5, total: 10, at: DateTime(2026, 7, 3)),
        result(subject: 'English', correct: 5, total: 10, at: DateTime(2026, 7, 4)),
        result(subject: 'English', correct: 5, total: 10, at: DateTime(2026, 7, 5)),
      ]);

      expect(stats.topSubject?.subject, 'Maths');
      expect(stats.topSubject?.questions, 40);
      expect(stats.subjects.map((s) => s.subject), ['Maths', 'English']);
    });

    test('sharpest subject needs enough questions to mean anything', () {
      final stats = build(results: [
        // Perfect, but only 10 questions — under the bar.
        result(subject: 'CRK', correct: 10, total: 10, at: DateTime(2026, 7, 2)),
        result(subject: 'Biology', correct: 24, total: 30, at: DateTime(2026, 7, 3)),
      ]);

      expect(stats.sharpestSubject?.subject, 'Biology');
      expect(stats.sharpestSubject?.accuracy, 80);
    });

    test('is null when nothing clears the bar', () {
      final stats = build(results: [
        result(subject: 'CRK', correct: 10, total: 10, at: DateTime(2026, 7, 2)),
      ]);

      expect(stats.sharpestSubject, isNull);
    });
  });

  group('time studied', () {
    test('sums only local attempts inside the month', () {
      final stats = build(
        results: [
          result(subject: 'Physics', correct: 8, total: 10, at: DateTime(2026, 7, 2)),
        ],
        attempts: [
          attempt(at: DateTime(2026, 7, 2), seconds: 600),
          attempt(at: DateTime(2026, 7, 9), seconds: 1800),
          attempt(at: DateTime(2026, 8, 1), seconds: 9999),
        ],
      );

      expect(stats.timeStudied, const Duration(minutes: 40));
    });

    test('is null when this device contributed nothing', () {
      final stats = build(results: [
        result(subject: 'Physics', correct: 8, total: 10, at: DateTime(2026, 7, 2)),
      ]);

      expect(stats.timeStudied, isNull);
    });
  });

  group('headline', () {
    test('showing up beats being accurate', () {
      final stats = build(results: [
        for (var day = 1; day <= 21; day++)
          result(subject: 'Physics', correct: 10, total: 10, at: DateTime(2026, 7, day)),
      ]);

      expect(stats.title, 'The Regular');
      expect(stats.subtitle, contains('21 days'));
    });

    test('an empty month says so rather than inventing a compliment', () {
      final stats = build();

      expect(stats.isEmpty, isTrue);
      expect(stats.title, 'The Quiet Month');
      expect(stats.accuracy, 0);
    });
  });

  group('formatDuration', () {
    test('renders hours and minutes the way a card needs them', () {
      expect(WrappedStats.formatDuration(const Duration(minutes: 45)), '45m');
      expect(WrappedStats.formatDuration(const Duration(hours: 2)), '2h');
      expect(
        WrappedStats.formatDuration(const Duration(hours: 3, minutes: 20)),
        '3h 20m',
      );
    });
  });

  group('monthKeyFor', () {
    test('zero-pads so keys sort as strings', () {
      expect(monthKeyFor(DateTime(2026, 7)), '2026-07');
      expect(monthKeyFor(DateTime(2026, 11)), '2026-11');
    });
  });
}
