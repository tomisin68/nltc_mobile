import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/broadcast.dart';
import '../services/api_client.dart';

/// The notice board.
class BroadcastRepository {
  BroadcastRepository({required ApiClient api, FirebaseFirestore? firestore})
      : _api = api,
        _db = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirebaseFirestore _db;

  /// Recent announcements, newest first.
  ///
  /// Falls back to reading `broadcasts` directly when the backend is asleep —
  /// the collection is world-readable to signed-in students, and an empty notice
  /// board reads as "nothing announced" rather than "couldn't ask".
  Future<List<Broadcast>> recent({int limit = 30}) async {
    try {
      final data = await _api.get('/broadcasts', query: {'limit': '$limit'});
      final rows = (data['broadcasts'] as List?) ?? const [];
      return rows
          .whereType<Map>()
          .map((e) => Broadcast.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      try {
        final snap = await _db
            .collection('broadcasts')
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .get();
        return snap.docs
            .map((d) => Broadcast.fromJson({...d.data(), 'id': d.id}))
            .toList();
      } catch (_) {
        return const [];
      }
    }
  }
}
