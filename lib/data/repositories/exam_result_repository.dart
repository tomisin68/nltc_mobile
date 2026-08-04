import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/exam_result.dart';
import '../services/firestore_cache.dart';

/// The server's record of every sitting this student has finished.
///
/// Cached under the same key the web uses (`userResults_{uid}`) with the same
/// TTL, so finishing a test in either place and then opening the other shows the
/// sitting rather than a stale table. Views that write a result invalidate this
/// key directly — see [cacheKeyFor].
class ExamResultRepository {
  ExamResultRepository({
    required FirestoreCache cache,
    FirebaseFirestore? firestore,
  })  : _cache = cache,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirestoreCache _cache;
  final FirebaseFirestore _db;

  static String cacheKeyFor(String uid) => 'userResults_$uid';

  /// Recent sittings, newest first.
  ///
  /// The cache layer stores JSON, so the maps are what get cached and the models
  /// are built on the way out. Caching the models directly would fail the disk
  /// write silently and leave only the memory layer working.
  Future<List<ExamResult>> recent(String uid, {int limit = 50}) async {
    final rows = await _cache.read<List<Map<String, dynamic>>>(
      cacheKeyFor(uid),
      CacheTtl.userResults,
      () async {
        try {
          final snap = await _db
              .collection('users')
              .doc(uid)
              .collection('results')
              .orderBy('submittedAt', descending: true)
              .limit(limit)
              .get();
          return snap.docs
              .map((d) => ExamResult.fromJson(d.id, d.data()).toJson())
              .toList();
        } catch (_) {
          // Offline, or the index is missing — an empty history reads the same as
          // a new account, which is the least alarming failure here.
          return const <Map<String, dynamic>>[];
        }
      },
      decode: (json) => (json as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );

    return rows
        .map((m) => ExamResult.fromJson(m['id'] as String? ?? '', m))
        .toList(growable: false);
  }

  /// Drops the cached history, so the next read reflects a sitting just finished.
  void invalidate(String uid) => _cache.invalidate(cacheKeyFor(uid));
}
