import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/data/repositories/question_report_repository.dart';
import 'package:nltc/data/repositories/question_repository.dart';
import 'package:nltc/domain/models/question.dart';

/// The report a student files against a suspect question.
///
/// Everything here is about the document body: `validQuestionFlag()` in
/// `firestore.rules` rejects the whole write if `status` is not `'open'`, if the
/// reason is empty or over 200 characters, or if the note runs past 500 — and
/// the student sees that as "reporting is not available", which sends them to a
/// tutor for a problem that is ours.
void main() {
  Question questionWith({
    String id = 'q1',
    String text = 'What is 5 × 6?',
    String? topic = 'Multiplication',
  }) =>
      Question(
        id: id,
        subject: 'Mathematics',
        text: text,
        options: const {'a': '25', 'b': '30'},
        answerKey: 'b',
        topic: topic,
      );

  Map<String, Object?> report({
    String note = '',
    String examMode = 'practice',
    String stage = 'exam',
    String? bank,
    Question? question,
  }) =>
      QuestionReportRepository.buildReport(
        uid: 'student-1',
        name: 'Ada',
        email: 'ada@example.com',
        question: question ?? questionWith(),
        subject: 'Mathematics',
        reason: QuestionReportRepository.reasons.first,
        note: note,
        examMode: examMode,
        stage: stage,
        bank: bank,
      );

  group('QuestionReportRepository.buildReport', () {
    test('opens in the state the rules demand, owned by the student', () {
      final doc = report();

      expect(doc['uid'], 'student-1');
      expect(doc['status'], 'open');
      expect(doc['reason'], isNotEmpty);
      expect(doc['questionId'], 'q1');
    });

    test('carries the wording so the report survives the question being fixed', () {
      final doc = report();

      expect(doc['questionText'], 'What is 5 × 6?');
      expect(doc['topic'], 'Multiplication');
      expect(doc['subject'], 'Mathematics');
    });

    test('a question with no topic reports an empty one, never null', () {
      // The admin list reads these straight onto badges; null would print there.
      expect(report(question: questionWith(topic: null))['topic'], '');
    });

    test('cuts a note down to the length the rules accept', () {
      final doc = report(note: 'x' * 900);

      expect(
        (doc['note']! as String).length,
        QuestionReportRepository.maxNoteLength,
      );
    });

    test('trims the note, so whitespace alone is not a comment', () {
      expect(report(note: '   options C and D match  ')['note'],
          'options C and D match');
    });

    test('cuts an enormous question down rather than sending the whole thing', () {
      final doc = report(question: questionWith(text: 'y' * 2000));

      expect((doc['questionText']! as String).length, 600);
    });

    test('BECE reports name the junior bank, everything else the senior one', () {
      expect(report(examMode: 'bece')['bank'], QuestionRepository.juniorBank);
      expect(report(examMode: 'jamb')['bank'], QuestionRepository.seniorBank);
      expect(report(examMode: 'mock')['bank'], QuestionRepository.seniorBank);
    });

    test('a bank the caller knows beats the one the exam mode implies', () {
      expect(
        report(examMode: 'topic', bank: QuestionRepository.juniorBank)['bank'],
        QuestionRepository.juniorBank,
      );
    });

    test('says whether the student could see the answer key when they filed', () {
      expect(report()['stage'], 'exam');
      expect(report(stage: 'review')['stage'], 'review');
    });
  });
}
