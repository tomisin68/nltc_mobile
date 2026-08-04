/// A teacher-written note on one topic, from the `studyNotes` collection.
class StudyNote {
  const StudyNote({
    required this.id,
    required this.topic,
    required this.subject,
    required this.content,
    this.order,
  });

  final String id;
  final String topic;
  final String subject;

  /// HTML, as the admin's rich-text editor produced it. Sanitised before render.
  final String content;

  /// Admin-set reading order. Notes without one sort after those with one, then
  /// alphabetically — same rule as the web.
  final int? order;

  static String _str(dynamic v) => v is String ? v.trim() : '';

  factory StudyNote.fromJson(String id, Map<String, dynamic> json) => StudyNote(
        id: id,
        topic: _str(json['topic']),
        subject: _str(json['subject']),
        content: _str(json['content']),
        order: json['order'] is num ? (json['order'] as num).toInt() : null,
      );
}

/// One row in a subject's topic list.
///
/// Topics come from the question bank, so a student can always practise a topic
/// even when nobody has written the note yet — that case shows as "Coming soon"
/// rather than being hidden, which is what tells a student the topic is examinable.
class NoteTopic {
  const NoteTopic({required this.topic, this.note});

  final String topic;
  final StudyNote? note;

  bool get hasNote => note != null && note!.content.isNotEmpty;
}
