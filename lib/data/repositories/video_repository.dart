import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/lesson_video.dart';

/// One topic shelf: a topic and the lessons filed under it.
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
  VideoRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

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

  /// Shelve [videos] by topic, A–Z.
  ///
  /// The topics are the lessons' own, so a student only ever sees shelves with
  /// something on them — we are not filming every topic on the syllabus, and a
  /// list that is mostly "coming soon" is a list nobody reads. Tags are matched
  /// case-insensitively, because the uploader and the question bank are two
  /// different typing surfaces; the first spelling seen labels the shelf.
  ///
  /// [kUntaggedTopic] sorts last wherever it lands alphabetically: it is the
  /// drawer for lessons nobody filed, not a topic in its own right.
  static List<TopicShelf> buildShelves(List<LessonVideo> videos) {
    final labels = <String, String>{};
    final grouped = <String, List<LessonVideo>>{};

    for (final video in videos) {
      final topic = video.topicOrDefault;
      final key = topic.toLowerCase().trim();
      labels.putIfAbsent(key, () => topic);
      grouped.putIfAbsent(key, () => []).add(video);
    }

    final untagged = kUntaggedTopic.toLowerCase();
    final order = grouped.keys.toList()
      ..sort((a, b) {
        final byDrawer = (a == untagged ? 1 : 0) - (b == untagged ? 1 : 0);
        return byDrawer != 0 ? byDrawer : labels[a]!.compareTo(labels[b]!);
      });

    return [
      for (final key in order)
        TopicShelf(topic: labels[key]!, videos: grouped[key]!),
    ];
  }
}
