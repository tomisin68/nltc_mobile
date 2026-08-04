import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/exam_attempt.dart';
import 'package:nltc/domain/models/question.dart';

Question _q(String id, {String answer = 'a'}) => Question(
      id: id,
      subject: 'Chemistry',
      text: 'Question $id',
      options: const {'a': 'One', 'b': 'Two', 'c': 'Three', 'd': 'Four'},
      answerKey: answer,
    );

void main() {
  group('ExamAttempt.grade', () {
    test('counts only the answers that match the key', () {
      final questions = [_q('1'), _q('2', answer: 'b'), _q('3')];

      final attempt = ExamAttempt.grade(
        id: 'attempt-1',
        subject: 'Chemistry',
        exam: 'JAMB / UTME',
        questions: questions,
        answers: const {'1': 'a', '2': 'c'},
        durationSeconds: 300,
      );

      expect(attempt.correct, 1);
      expect(attempt.total, 3);
      expect(attempt.answeredCount, 2);
      expect(attempt.skippedCount, 1);
    });

    test('scores to one decimal, matching the backend formula', () {
      final attempt = ExamAttempt.grade(
        id: 'attempt-2',
        subject: 'Chemistry',
        exam: 'WAEC',
        questions: [_q('1'), _q('2'), _q('3')],
        answers: const {'1': 'a', '2': 'a'},
        durationSeconds: 60,
      );

      expect(attempt.score, 66.7);
    });

    test('a sitting with nothing answered scores zero rather than throwing', () {
      final attempt = ExamAttempt.grade(
        id: 'attempt-3',
        subject: 'Chemistry',
        exam: 'NECO',
        questions: [_q('1')],
        answers: const {},
        durationSeconds: 5,
      );

      expect(attempt.correct, 0);
      expect(attempt.score, 0);
      expect(attempt.syncState, SyncState.pending);
    });

    test('preserves the order the questions were served in', () {
      final attempt = ExamAttempt.grade(
        id: 'attempt-4',
        subject: 'Chemistry',
        exam: 'JAMB / UTME',
        questions: [_q('c'), _q('a'), _q('b')],
        answers: const {},
        durationSeconds: 1,
      );

      expect(attempt.questionIds, ['c', 'a', 'b']);
    });
  });

  group('SQLite round trip', () {
    test('survives the row mapping unchanged', () {
      final original = ExamAttempt.grade(
        id: 'attempt-5',
        subject: 'Physics',
        exam: 'WAEC',
        topic: 'Waves',
        questions: [_q('1'), _q('2', answer: 'd')],
        answers: const {'1': 'a', '2': 'd'},
        durationSeconds: 42,
      ).copyWith(syncState: SyncState.failed, syncAttempts: 3);

      final restored = ExamAttempt.fromRow(original.toRow());

      expect(restored.id, original.id);
      expect(restored.topic, 'Waves');
      expect(restored.questionIds, original.questionIds);
      expect(restored.answers, original.answers);
      expect(restored.correct, 2);
      expect(restored.syncState, SyncState.failed);
      expect(restored.syncAttempts, 3);
      expect(
        restored.submittedAt.millisecondsSinceEpoch,
        original.submittedAt.millisecondsSinceEpoch,
      );
    });

    test('a corrupt answers column costs the answers, not the row', () {
      final row = ExamAttempt.grade(
        id: 'attempt-6',
        subject: 'Physics',
        exam: 'WAEC',
        questions: [_q('1')],
        answers: const {'1': 'a'},
        durationSeconds: 10,
      ).toRow();
      row['answers'] = '{not json';

      final restored = ExamAttempt.fromRow(row);

      expect(restored.id, 'attempt-6');
      expect(restored.answers, isEmpty);
    });
  });

  group('toSyncPayload', () {
    test('sends the fields the cbt-session route validates', () {
      final payload = ExamAttempt.grade(
        id: 'attempt-7',
        subject: 'Biology',
        exam: 'JAMB / UTME',
        topic: 'Genetics',
        questions: [_q('1'), _q('2')],
        answers: const {'1': 'a'},
        durationSeconds: 90,
      ).toSyncPayload();

      expect(payload['subject'], 'Biology');
      expect(payload['exam'], 'JAMB / UTME');
      expect(payload['topic'], 'Genetics');
      expect(payload['correct'], 1);
      expect(payload['total'], 2);
      expect(payload['score'], 50.0);
      expect(payload['clientAttemptId'], 'attempt-7');
    });

    test('omits topic entirely when the sitting had none', () {
      final payload = ExamAttempt.grade(
        id: 'attempt-8',
        subject: 'Biology',
        exam: 'JAMB / UTME',
        questions: [_q('1')],
        answers: const {'1': 'a'},
        durationSeconds: 5,
      ).toSyncPayload();

      expect(payload.containsKey('topic'), isFalse);
    });
  });
}
