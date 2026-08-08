import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/lesson_video.dart';
import '../services/firestore_cache.dart';

/// One topic shelf: a question-bank topic and the lessons filed under it.
class TopicShelf {
  const TopicShelf({required this.topic, required this.videos});

  final String topic;
  final List<LessonVideo> videos;

  bool get hasVideos => videos.isNotEmpty;

  /// Distinct experts behind the lessons — "3 lessons from 2 experts".
  int get expertCount => {
    for (final v in videos)
      if (v.teacher != null) v.teacher!,
  }.length;
}

/// The lesson library.
class VideoRepository {
  VideoRepository({required FirestoreCache cache, FirebaseFirestore? firestore})
      : _cache = cache,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirestoreCache _cache;
  final FirebaseFirestore _db;

  /// Live library, newest first — the web uses `onSnapshot` here so a lesson the
  /// admin uploads mid-session appears without a reload.
  ///
  /// Firestore serves this from its own cache while offline, so a student who
  /// browsed the library before losing signal still sees it.
  Stream<List<LessonVideo>> watch() => _db
      .collection('videos')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => LessonVideo.fromJson(d.id, d.data()))
            .toList(growable: false),
      );

  /// Distinct topic tags in the question bank for one subject.
  ///
  /// Firestore has no DISTINCT, so this reads the subject's questions and reduces
  /// client-side — exactly what the web's `fetchBankTopics` does, and why both
  /// sides cache it.
  Future<List<String>> bankTopics(String subjectName) => _cache.read(
        'videoBankTopics_$subjectName',
        CacheTtl.quickTests,
        () async {
          try {
            final snap = await _db
                .collection('questions')
                .where('subject', isEqualTo: subjectName)
                .get();
            final topics = <String>{};
            for (final doc in snap.docs) {
              final topic = doc.data()['topic'];
              if (topic is String && topic.trim().isNotEmpty) {
                topics.add(topic.trim());
              }
            }
            return topics.toList()..sort();
          } catch (_) {
            // Offline or rules rejected the read — the shelves built from the
            // videos alone are still worth showing.
            return const <String>[];
          }
        },
        decode: (json) => (json as List).map((e) => e as String).toList(),
      );

  /// Group [videos] onto [topics], the question bank's list.
  ///
  /// The bank decides which topics exist; videos hang off them, matched
  /// case-insensitively because the two lists are typed in different admin
  /// screens. A video whose topic no longer matches a bank tag — renamed after
  /// upload, say — keeps a shelf of its own rather than disappearing.
  static List<TopicShelf> buildShelves(
    List<String> topics,
    List<LessonVideo> videos,
  ) {
    final order = <String>[];
    final labels = <String, String>{};
    final grouped = <String, List<LessonVideo>>{};

    void ensure(String topic) {
      final key = topic.toLowerCase().trim();
      if (grouped.containsKey(key)) return;
      order.add(key);
      labels[key] = topic;
      grouped[key] = [];
    }

    for (final topic in topics) {
      ensure(topic);
    }
    final bankKeys = {for (final t in topics) t.toLowerCase().trim()};

    for (final video in videos) {
      final topic = video.topicOrDefault;
      ensure(topic);
      grouped[topic.toLowerCase().trim()]!.add(video);
    }

    // Bank topics first, then anything a video invented; A–Z within each group.
    order.sort((a, b) {
      final byBank = (bankKeys.contains(a) ? 0 : 1) - (bankKeys.contains(b) ? 0 : 1);
      return byBank != 0 ? byBank : labels[a]!.compareTo(labels[b]!);
    });

    return [
      for (final key in order)
        TopicShelf(topic: labels[key]!, videos: grouped[key]!),
    ];
  }
}
