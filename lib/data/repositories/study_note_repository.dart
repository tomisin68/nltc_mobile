import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/study_note.dart';
import '../../domain/models/subject.dart';
import '../services/firestore_cache.dart';

/// Study notes, and the topic list they hang off.
///
/// Port of the loading logic in `src/pages/dashboard/StudyNotesView.jsx`. The
/// topic list is the union of two sources: distinct `topic` values in the
/// question bank, and any note whose topic no longer matches one — so a note
/// written before an admin renamed a bank topic is still reachable rather than
/// silently lost.
class StudyNoteRepository {
  StudyNoteRepository({
    required FirestoreCache cache,
    FirebaseFirestore? firestore,
  })  : _cache = cache,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirestoreCache _cache;
  final FirebaseFirestore _db;

  /// The bank a category's questions live in. Junior questions are a separate
  /// collection, not a field on the senior one.
  static String bankFor(SubjectCategory category) =>
      category == SubjectCategory.junior ? 'jssQuestions' : 'questions';

  /// Every topic for [subjectName], each paired with its note when one exists.
  Future<List<NoteTopic>> topics({
    required String subjectName,
    required SubjectCategory category,
  }) async {
    final bank = bankFor(category);

    final results = await Future.wait([
      _bankTopics(bank, subjectName),
      _notes(category, subjectName),
    ]);
    final bankTopics = results[0] as List<String>;
    final notes = results[1] as List<StudyNote>;

    // Matched case-insensitively: bank topics and note topics are typed by hand
    // in two different admin screens, so their capitalisation drifts.
    final notesByTopic = {
      for (final note in notes) note.topic.toLowerCase(): note,
    };

    final merged = [
      for (final topic in bankTopics)
        NoteTopic(topic: topic, note: notesByTopic[topic.toLowerCase()]),
    ];

    final bankKeys = bankTopics.map((t) => t.toLowerCase()).toSet();
    for (final note in notes) {
      if (note.topic.isNotEmpty && !bankKeys.contains(note.topic.toLowerCase())) {
        merged.add(NoteTopic(topic: note.topic, note: note));
      }
    }

    merged.sort((a, b) {
      final byOrder = (a.note?.order ?? 9999).compareTo(b.note?.order ?? 9999);
      return byOrder != 0 ? byOrder : a.topic.compareTo(b.topic);
    });
    return merged;
  }

  /// Distinct topic tags in the question bank for one subject.
  ///
  /// Firestore has no DISTINCT, so this reads the subject's questions and reduces
  /// client-side — which is exactly what the web does, and why it is cached.
  Future<List<String>> _bankTopics(String bank, String subjectName) => _cache.read(
        'studyNotesBankTopics_${bank}_$subjectName',
        CacheTtl.quickTests,
        () async {
          try {
            final snap = await _db
                .collection(bank)
                .where('subject', isEqualTo: subjectName)
                .get();
            final topics = <String>{};
            for (final doc in snap.docs) {
              final topic = doc.data()['topic'];
              if (topic is String && topic.trim().isNotEmpty) {
                topics.add(topic.trim());
              }
            }
            return topics.toList();
          } catch (_) {
            return const <String>[];
          }
        },
        decode: (json) => (json as List).map((e) => e as String).toList(),
      );

  Future<List<StudyNote>> _notes(
    SubjectCategory category,
    String subjectName,
  ) async {
    try {
      final snap = await _db
          .collection('studyNotes')
          .where('category', isEqualTo: category.wireName)
          .where('subject', isEqualTo: subjectName)
          .get();
      return snap.docs
          .map((d) => StudyNote.fromJson(d.id, d.data()))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
