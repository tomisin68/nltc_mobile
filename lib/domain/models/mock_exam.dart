import 'app_user.dart' show tsToMs;

/// One subject line on a mock exam: which subject, and how many questions.
class MockExamSubject {
  const MockExamSubject({required this.subject, required this.count});

  final String subject;
  final int count;

  factory MockExamSubject.fromJson(Map<String, dynamic> json) =>
      MockExamSubject(
        subject: (json['subject'] as String?)?.trim() ?? '',
        count: json['count'] is num ? (json['count'] as num).toInt() : 0,
      );
}

/// A published mock exam from the `mockExams` collection.
class MockExam {
  const MockExam({
    required this.id,
    required this.title,
    required this.subjects,
    this.type,
    this.department,
    this.totalDuration = 0,
    this.resultsPublished = false,
  });

  final String id;
  final String title;
  final List<MockExamSubject> subjects;

  /// `jamb`, `waec`, `neco` or `postutme`.
  final String? type;

  /// `science`, `art`, `commercial` or `general`.
  final String? department;

  /// Minutes for the whole paper.
  final int totalDuration;

  /// Until a teacher publishes results, a submitted exam shows as pending and its
  /// score is withheld — that is the point of a mock.
  final bool resultsPublished;

  int get questionCount =>
      subjects.fold(0, (sum, s) => sum + s.count);

  String get subjectLine => subjects.map((s) => s.subject).join(' · ');

  static const typeLabels = <String, String>{
    'jamb': 'JAMB MOCK',
    'waec': 'SSCE MOCK',
    'neco': 'NECO MOCK',
    'postutme': 'Post UTME MOCK',
  };

  static const departmentLabels = <String, String>{
    'science': 'Science',
    'art': 'Art',
    'commercial': 'Commercial',
    'general': 'General',
  };

  String get typeLabel =>
      typeLabels[type] ?? (type ?? 'MOCK').toUpperCase();

  String? get departmentLabel =>
      department == null ? null : (departmentLabels[department] ?? department);

  factory MockExam.fromJson(String id, Map<String, dynamic> json) => MockExam(
        id: id,
        title: (json['title'] as String?)?.trim() ?? 'Mock exam',
        type: (json['type'] as String?)?.trim(),
        department: (json['department'] as String?)?.trim(),
        totalDuration: json['totalDuration'] is num
            ? (json['totalDuration'] as num).toInt()
            : 0,
        resultsPublished: json['resultsPublished'] == true,
        subjects: ((json['subjects'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => MockExamSubject.fromJson(Map<String, dynamic>.from(e)))
            .where((s) => s.subject.isNotEmpty && s.count > 0)
            .toList(growable: false),
      );
}

/// Per-subject marks inside a submission.
class SubjectScore {
  const SubjectScore({
    required this.subject,
    required this.correct,
    required this.total,
  });

  final String subject;
  final int correct;
  final int total;

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'correct': correct,
        'total': total,
      };

  factory SubjectScore.fromJson(Map<String, dynamic> json) => SubjectScore(
        subject: (json['subject'] as String?) ?? '',
        correct: json['correct'] is num ? (json['correct'] as num).toInt() : 0,
        total: json['total'] is num ? (json['total'] as num).toInt() : 0,
      );
}

/// A student's submission for one mock exam.
class MockSubmission {
  const MockSubmission({
    required this.score,
    required this.correct,
    required this.total,
    this.subjectBreakdown = const [],
    this.xpAwarded = false,
    this.submittedAt,
    this.attempts = const [],
  });

  /// Percentage.
  final int score;

  final int correct;
  final int total;
  final List<SubjectScore> subjectBreakdown;

  /// Set once XP has been credited, so revisiting a published result cannot
  /// award it twice — this flag lives on the server for exactly that reason.
  final bool xpAwarded;

  final DateTime? submittedAt;

  /// Every attempt, oldest first. In practice a mock allows one, but the history
  /// exists for records created before that rule and for admin re-opens.
  final List<MockSubmission> attempts;

  factory MockSubmission.fromJson(
    Map<String, dynamic> json, {
    List<MockSubmission> attempts = const [],
  }) {
    final ms = tsToMs(json['submittedAt']);
    return MockSubmission(
      score: json['score'] is num ? (json['score'] as num).round() : 0,
      correct: json['correct'] is num ? (json['correct'] as num).toInt() : 0,
      total: json['total'] is num ? (json['total'] as num).toInt() : 0,
      xpAwarded: json['xpAwarded'] == true,
      submittedAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      subjectBreakdown: ((json['subjectBreakdown'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SubjectScore.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      attempts: attempts,
    );
  }
}
