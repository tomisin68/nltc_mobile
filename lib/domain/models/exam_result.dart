import 'app_user.dart' show tsToMs;

/// One finished sitting from `users/{uid}/results`, written by the backend when
/// it accepts a CBT session.
///
/// This is the server's record, distinct from the local `ExamAttempt` in SQLite:
/// it covers sittings taken on the website too, which is what makes the history
/// table match between app and web.
class ExamResult {
  const ExamResult({
    required this.id,
    required this.subject,
    required this.correct,
    required this.total,
    this.exam,
    this.topic,
    this.submittedAt,
  });

  final String id;
  final String subject;
  final int correct;
  final int total;

  /// `jamb`, `waec`, `postutme`, `practice`, `nltc_quiz`, `quick_test`, `mock`,
  /// `topic`, `bece`, `custom`.
  final String? exam;

  final String? topic;
  final DateTime? submittedAt;

  int get percent => total == 0 ? 0 : (correct / total * 100).round();

  static const _examLabels = <String, String>{
    'jamb': 'JAMB',
    'waec': 'WAEC',
    'postutme': 'Post UTME',
    'practice': 'Practice',
    'nltc_quiz': 'Official Quiz',
    'quick_test': 'Quick Test',
    'mock': 'Mock Exam',
    'topic': 'Topic Test',
    'bece': 'BECE',
    'custom': 'Custom CBT',
  };

  String get examLabel =>
      _examLabels[exam] ?? (exam ?? 'CBT').toUpperCase();

  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  static int _int(dynamic v) => v is num ? v.toInt() : 0;

  factory ExamResult.fromJson(String id, Map<String, dynamic> json) {
    final ms = tsToMs(json['submittedAt']);
    return ExamResult(
      id: id,
      subject: _str(json['subject']) ?? 'Unknown',
      correct: _int(json['correct']),
      total: _int(json['total']),
      exam: _str(json['exam']),
      topic: _str(json['topic']),
      submittedAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  /// Round-trips through the read cache, which stores plain JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'correct': correct,
        'total': total,
        'exam': exam,
        'topic': topic,
        'submittedAt': submittedAt?.millisecondsSinceEpoch,
      };
}
