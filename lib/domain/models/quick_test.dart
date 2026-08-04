import 'app_user.dart' show tsToMs;

/// One question inside a quick test or a mock exam.
///
/// The admin uploader writes options either as `a`/`b`/`c`/`d` or as
/// `option_a`…`option_d`, depending on which screen created it, so both shapes
/// have to be read. `answer` is the letter of the correct option.
class InlineQuestion {
  const InlineQuestion({
    required this.question,
    required this.options,
    required this.answer,
    this.explanation,
  });

  final String question;

  /// Letter → option text, in `a`…`d` order, with blanks dropped: a
  /// three-option question is legitimate and must not render an empty fourth.
  final Map<String, String> options;

  /// The correct letter, lowercased.
  final String answer;

  final String? explanation;

  bool isCorrect(String? chosen) => chosen != null && chosen == answer;

  static String _str(dynamic v) => v is String ? v.trim() : '';

  factory InlineQuestion.fromJson(Map<String, dynamic> json) {
    final options = <String, String>{};
    for (final letter in const ['a', 'b', 'c', 'd']) {
      final text = _str(json[letter]).isNotEmpty
          ? _str(json[letter])
          : _str(json['option_$letter']);
      if (text.isNotEmpty) options[letter] = text;
    }
    return InlineQuestion(
      question: _str(json['question']),
      options: options,
      answer: _str(json['answer']).toLowerCase(),
      explanation:
          _str(json['explanation']).isEmpty ? null : _str(json['explanation']),
    );
  }
}

/// A short published test from the `quickTests` collection.
class QuickTest {
  const QuickTest({
    required this.id,
    required this.title,
    required this.questions,
    this.subject,
    this.durationMinutes,
    this.createdAt,
  });

  final String id;
  final String title;
  final List<InlineQuestion> questions;
  final String? subject;
  final int? durationMinutes;
  final DateTime? createdAt;

  factory QuickTest.fromJson(String id, Map<String, dynamic> json) {
    final raw = (json['questions'] as List?) ?? const [];
    return QuickTest(
      id: id,
      title: (json['title'] as String?)?.trim() ?? 'Quick test',
      subject: (json['subject'] as String?)?.trim(),
      durationMinutes:
          json['duration'] is num ? (json['duration'] as num).toInt() : null,
      questions: raw
          .whereType<Map>()
          .map((e) => InlineQuestion.fromJson(Map<String, dynamic>.from(e)))
          // A question with no text or no options cannot be answered; dropping it
          // beats rendering a blank card the student can't get past.
          .where((q) => q.question.isNotEmpty && q.options.isNotEmpty)
          .toList(growable: false),
      createdAt: (() {
        final ms = tsToMs(json['createdAt']);
        return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
      })(),
    );
  }
}
