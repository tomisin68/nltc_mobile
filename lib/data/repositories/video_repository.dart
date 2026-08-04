import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/lesson_video.dart';

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
}
