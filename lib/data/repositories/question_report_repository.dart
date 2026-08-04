import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/question.dart';
import 'question_repository.dart';

/// A student reporting a suspect question — `flaggedQuestions/{id}`.
///
/// Writes exactly the documents the website files from `handleFlagQuestion` in
/// `src/pages/CBTPage.jsx`, so Flagged Questions in the admin panel shows one
/// kind of report whether it came from a browser or a phone. The rules that
/// accept it (`validQuestionFlag()` in `firestore.rules`) are already deployed
/// for the web, so nothing has to ship before this works.
class QuestionReportRepository {
  QuestionReportRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// What a student can say is wrong, in the website's wording and order —
  /// `FLAG_REASONS` in `src/components/exam/FlagQuestionButton.jsx`.
  static const reasons = <String>[
    'No correct option listed',
    'More than one option looks correct',
    'Question or option text is unclear / cut off',
    'Missing or broken image',
    'Wrong subject or topic',
    'Something else',
  ];

  /// The ceilings `validQuestionFlag()` enforces. A note over the limit is cut
  /// rather than rejected — a student who typed too much should not lose it.
  static const maxNoteLength = 500;
  static const _maxSnapshotLength = 600;

  /// Question ids reported while the app has been open.
  ///
  /// Not persisted, and deliberately keyed by question rather than by position:
  /// it exists so the same question reported during the paper is still shown as
  /// reported when it comes round again in the corrections, and so a student
  /// cannot file the same complaint twice on one screen. The report itself
  /// lives in Firestore.
  final Set<String> _reported = <String>{};

  bool hasReported(String questionId) => _reported.contains(questionId);

  /// Which collection a sitting's questions came from. BECE reads the junior
  /// bank; everything else reads the senior one — the same rule the web applies
  /// when it stamps `bank` on a report.
  static String bankFor(String examMode) => examMode == 'bece'
      ? QuestionRepository.juniorBank
      : QuestionRepository.seniorBank;

  /// Files one report.
  ///
  /// [stage] is `'exam'` from the hall and `'review'` from the corrections. It
  /// matters to whoever reads the queue: a student mid-paper can only doubt the
  /// wording, but one in review has seen the answer key and can say it is wrong.
  Future<void> report({
    required String uid,
    required String name,
    required String email,
    required Question question,
    required String subject,
    required String reason,
    String note = '',
    String examMode = 'practice',
    String stage = 'exam',
    String? bank,
  }) async {
    await _db.collection('flaggedQuestions').add({
      ...buildReport(
        uid: uid,
        name: name,
        email: email,
        question: question,
        subject: subject,
        reason: reason,
        note: note,
        examMode: examMode,
        stage: stage,
        bank: bank,
      ),
      'createdAt': FieldValue.serverTimestamp(),
    });
    _reported.add(question.id);
  }

  /// The document body, minus the server timestamp.
  ///
  /// Split out so the shape can be tested without a Firestore: every field
  /// `validQuestionFlag()` inspects is decided here, and getting one wrong is a
  /// permission error in a student's face rather than anything louder.
  static Map<String, Object?> buildReport({
    required String uid,
    required String name,
    required String email,
    required Question question,
    required String subject,
    required String reason,
    String note = '',
    String examMode = 'practice',
    String stage = 'exam',
    String? bank,
  }) =>
      {
        'uid': uid,
        'userName': name,
        'userEmail': email,
        'questionId': question.id,
        'bank': bank ?? bankFor(examMode),
        'subject': subject,
        'topic': question.topic ?? '',
        // A snapshot of the wording, so the report still reads sensibly once
        // the question has been edited — or deleted — in response to it.
        'questionText': _clip(question.text, _maxSnapshotLength),
        'reason': reason,
        'note': _clip(note.trim(), maxNoteLength),
        'examMode': examMode,
        'stage': stage,
        'status': 'open',
      };

  static String _clip(String value, int limit) =>
      value.length > limit ? value.substring(0, limit) : value;
}
