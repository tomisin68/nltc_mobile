import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/mock_exam.dart';

/// Published mock exams and this student's submissions against them.
class MockExamRepository {
  MockExamRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Every published mock exam.
  ///
  /// Throws rather than swallowing: the web shows a "could not load" panel with a
  /// Retry button here, and it needs the error to do that.
  Future<List<MockExam>> published() async {
    final snap = await _db
        .collection('mockExams')
        .where('status', isEqualTo: 'published')
        .get();
    return snap.docs
        .map((d) => MockExam.fromJson(d.id, d.data()))
        .toList(growable: false);
  }

  DocumentReference<Map<String, dynamic>> _submissionRef(
    String examId,
    String uid,
  ) =>
      _db.collection('mockExams').doc(examId).collection('submissions').doc(uid);

  /// This student's submission for [examId], with its attempt history, or null if
  /// they have not sat it.
  Future<MockSubmission?> submission(String examId, String uid) async {
    try {
      final snap = await _submissionRef(examId, uid).get();
      if (!snap.exists) return null;

      final attemptsSnap =
          await _submissionRef(examId, uid).collection('attempts').get();
      final attempts = attemptsSnap.docs
          .map((d) => MockSubmission.fromJson(d.data()))
          .toList()
        ..sort((a, b) {
          final at = a.submittedAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.submittedAt?.millisecondsSinceEpoch ?? 0;
          return at.compareTo(bt);
        });

      return MockSubmission.fromJson(snap.data() ?? const {}, attempts: attempts);
    } catch (_) {
      // A missing submission and an unreadable one look the same to the student:
      // the exam simply shows as not yet taken.
      return null;
    }
  }

  /// Loads every student's submission state for a list of exams, in parallel.
  Future<Map<String, MockSubmission>> submissions(
    List<MockExam> exams,
    String uid,
  ) async {
    final results = await Future.wait(
      exams.map((e) async => (id: e.id, submission: await submission(e.id, uid))),
    );
    return {
      for (final r in results)
        if (r.submission != null) r.id: r.submission!,
    };
  }

  /// Records a finished sitting.
  ///
  /// Two writes, matching the web: the submission document holds the latest
  /// attempt for the admin results view, and a new document in `attempts` keeps
  /// the student's own history.
  ///
  /// [displayName] and [elapsedSeconds] are for the admin's results table, not
  /// for this app — nothing here reads them back. They were missing, so every
  /// sitting taken on a phone arrived in that table as a blank name and a dash
  /// where the time should be, while the same exam sat on the website showed
  /// both. The document id is the uid, but the admin list reads the field, and
  /// a column of truncated uids is not a register of who sat the paper.
  Future<void> saveSubmission({
    required String examId,
    required String uid,
    required String displayName,
    required int score,
    required int correct,
    required int total,
    required int elapsedSeconds,
    required List<SubjectScore> subjectBreakdown,
    required Map<String, String> answers,
    required List<String> questionIds,
  }) async {
    final payload = {
      'uid': uid,
      'displayName': displayName,
      'score': score,
      'correct': correct,
      'total': total,
      'elapsed': elapsedSeconds,
      'subjectBreakdown': subjectBreakdown.map((s) => s.toJson()).toList(),
      'submittedAt': FieldValue.serverTimestamp(),
      // Which questions were served and how they were answered, so the exact
      // paper can be rebuilt for review once results are published.
      'questionIds': questionIds,
      'answers': answers,
    };

    await _submissionRef(examId, uid).set(payload, SetOptions(merge: true));
    await _submissionRef(examId, uid).collection('attempts').add(payload);
  }

  /// Flags XP as credited for this submission, so it cannot be awarded twice.
  Future<void> markXpAwarded(String examId, String uid) =>
      _submissionRef(examId, uid).set(
        {'xpAwarded': true},
        SetOptions(merge: true),
      );
}
