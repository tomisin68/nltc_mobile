import 'dart:convert';

/// A single multiple-choice question.
///
/// The Firestore `questions` collection has accumulated three different option
/// shapes over the years — the admin uploader writes flat `a`/`b`/`c`/`d` keys
/// today, but older rows use `option_a` or a nested `options` map, and the
/// answer key is either `answer` or `correct_option`. [Question.fromMap]
/// normalises all of them so the rest of the app only ever sees one shape.
///
/// This mirrors `getOptionText()` / `getAnswer()` in the web app's CBTPage.
class Question {
  const Question({
    required this.id,
    required this.subject,
    required this.text,
    required this.options,
    required this.answerKey,
    this.topic,
    this.year,
    this.explanation,
    this.examType,
    this.difficulty,
    this.imageUrl,
    this.eloRating,
    this.passageId,
    this.passageOrder,
  });

  final String id;
  final String subject;
  final String text;

  /// Option keys → text, e.g. `{'a': 'Lagos', 'b': 'Abuja'}`.
  /// Only non-empty options are kept, so a 3-option question renders as three.
  final Map<String, String> options;

  /// Lower-cased key of the correct option: `'a'`, `'b'`, `'c'` or `'d'`.
  final String answerKey;

  final String? topic;
  final int? year;
  final String? explanation;
  final String? examType;
  final String? difficulty;

  /// A diagram the question depends on — geometry, circuits, graphs. Downloaded
  /// packs keep the URL, not the bytes, so an offline sitting shows a
  /// placeholder rather than pretending the picture is there.
  final String? imageUrl;

  /// The adaptive engine's rating for this question, when it has scored one.
  /// Null means fall back to the difficulty label's seed rating.
  final double? eloRating;

  /// Which passage this question belongs to, for the comprehension and cloze
  /// questions that only make sense alongside the others about the same text.
  /// Null on every other question, which is nearly all of them.
  final String? passageId;

  /// Where this question sits inside its passage, counted from 0.
  ///
  /// Stored rather than inferred: cloze gaps have to run in the order the
  /// passage reads, and Firestore returns documents in no order worth relying
  /// on. Written by the spreadsheet import from the row's position in the file.
  final int? passageOrder;

  static const optionKeys = ['a', 'b', 'c', 'd'];

  /// Reads one option across all three historical field shapes.
  static String _readOption(Map<String, dynamic> m, String k) {
    final direct = m[k];
    if (direct is String && direct.trim().isNotEmpty) return direct.trim();

    final prefixed = m['option_$k'];
    if (prefixed is String && prefixed.trim().isNotEmpty) return prefixed.trim();

    for (final nestedKey in ['options', 'option']) {
      final nested = m[nestedKey];
      if (nested is Map) {
        final v = nested[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return '';
  }

  factory Question.fromMap(String id, Map<String, dynamic> m) {
    final options = <String, String>{};
    for (final k in optionKeys) {
      final text = _readOption(m, k);
      if (text.isNotEmpty) options[k] = text;
    }

    final rawAnswer =
        (m['answer'] ?? m['correct_option'] ?? m['correctAnswer'] ?? '')
            .toString()
            .toLowerCase()
            .trim();

    return Question(
      id: id,
      subject: (m['subject'] ?? '').toString().trim(),
      text: (m['question'] ?? '').toString().trim(),
      options: options,
      // Fall back to 'a' rather than throwing: a malformed row should cost one
      // question, not break a student's whole exam.
      answerKey: optionKeys.contains(rawAnswer) ? rawAnswer : 'a',
      topic: (m['topic'] as String?)?.trim(),
      year: m['year'] is int ? m['year'] as int : int.tryParse('${m['year']}'),
      // `solution` is what the older uploader wrote; the web falls back the
      // same way so a question explained on one side is explained on both.
      explanation: _text(m['explanation']) ?? _text(m['solution']),
      examType: (m['examType'] as String?)?.trim(),
      difficulty: (m['difficulty'] as String?)?.trim(),
      imageUrl: _text(m['image']) ?? _text(m['imageUrl']),
      eloRating:
          m['eloRating'] is num ? (m['eloRating'] as num).toDouble() : null,
      passageId: _text(m['passageId']) ?? _text(m['passage_id']),
      // Firestore hands a whole number back as an int or a double depending on
      // how it was written, and the import writes it as a number either way.
      passageOrder: m['passageOrder'] is num
          ? (m['passageOrder'] as num).toInt()
          : int.tryParse('${m['passageOrder'] ?? ''}'),
    );
  }

  static String? _text(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  /// A question is only usable if it has text, at least two choices, and an
  /// answer key that actually points at one of them.
  bool get isUsable =>
      text.isNotEmpty && options.length >= 2 && options.containsKey(answerKey);

  bool isCorrect(String? chosenKey) => chosenKey == answerKey;

  // ─── SQLite row mapping ─────────────────────────────────────────────────
  // Options ride in one JSON column rather than four fixed columns so adding a
  // fifth choice later needs no schema migration.

  Map<String, Object?> toRow() => {
        'id': id,
        'subject': subject,
        'text': text,
        'options': jsonEncode(options),
        'answer_key': answerKey,
        'topic': topic,
        'year': year,
        'explanation': explanation,
        'exam_type': examType,
        'difficulty': difficulty,
        'image_url': imageUrl,
        'elo_rating': eloRating,
        'passage_id': passageId,
        'passage_order': passageOrder,
      };

  factory Question.fromRow(Map<String, Object?> r) => Question(
        id: r['id'] as String,
        subject: r['subject'] as String? ?? '',
        text: r['text'] as String? ?? '',
        options: _decodeOptions(r['options'] as String?),
        answerKey: r['answer_key'] as String? ?? 'a',
        topic: r['topic'] as String?,
        year: r['year'] as int?,
        explanation: r['explanation'] as String?,
        examType: r['exam_type'] as String?,
        difficulty: r['difficulty'] as String?,
        imageUrl: r['image_url'] as String?,
        eloRating: (r['elo_rating'] as num?)?.toDouble(),
        passageId: r['passage_id'] as String?,
        passageOrder: (r['passage_order'] as num?)?.toInt(),
      );

  static Map<String, String> _decodeOptions(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry('$k', '$v'));
      }
    } catch (_) {
      // A corrupt cached row costs one question, not the whole exam.
    }
    return {};
  }
}
