import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/app_user.dart';

/// One student's review of NLTC itself.
class PlatformReview {
  const PlatformReview({
    required this.rating,
    required this.body,
    required this.status,
  });

  final int rating;
  final String body;

  /// `pending`, `published` or `hidden` — set by moderation, never by the app.
  final String status;

  bool get isPublished => status == 'published';
}

/// Reads and writes `platformReviews/{uid}`.
///
/// The document id IS the student's uid, which makes "one review per student" a
/// property of the data rather than a rule somebody has to remember to check.
///
/// Every write lands as `pending`, including an edit of an already-published
/// review — otherwise a review could be published clean and then rewritten into
/// something else. The collection is world-readable so the marketing site can
/// show published reviews, and an unmoderated world-readable text field on a
/// platform full of under-18s is a liability rather than a feature. The
/// Firestore rules enforce that too; this class is not the only guard.
class PlatformReviewRepository {
  PlatformReviewRepository();

  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('platformReviews');

  /// This student's review, or null if they have never left one.
  ///
  /// Returns null rather than throwing when the read fails: every caller treats
  /// "no review" and "could not tell" the same way, and a review form that
  /// refuses to open because Firestore was slow helps nobody.
  Future<PlatformReview?> mine(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final snap = await _collection.doc(uid).get();
      final data = snap.data();
      if (data == null) return null;
      return PlatformReview(
        rating: (data['rating'] as num?)?.toInt() ?? 0,
        body: (data['body'] as String?) ?? '',
        status: (data['status'] as String?) ?? 'pending',
      );
    } catch (_) {
      return null;
    }
  }

  /// Saves [rating] and [body], stamping the student's public identity onto it.
  ///
  /// The name and photo are copied in rather than joined at read time so the
  /// marketing site can render a published review without reading the whole
  /// user document — which it has no business being able to do.
  Future<void> save({
    required String uid,
    required AppUser? profile,
    required int rating,
    required String body,
    required bool isFirst,
  }) async {
    final name = [profile?.firstName, profile?.lastName]
        .where((p) => p != null && p.trim().isNotEmpty)
        .join(' ')
        .trim();

    await _collection.doc(uid).set({
      'uid': uid,
      'name': name.isEmpty ? 'Student' : name,
      'photo': profile?.profileImage,
      'targetExam': profile?.targetExam,
      'rating': rating,
      'body': body.trim(),
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
      if (isFirst) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
