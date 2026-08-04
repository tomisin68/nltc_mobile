import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/leaderboard_entry.dart';
import '../../domain/models/xp_result.dart';
import '../services/api_client.dart';

/// XP, streaks and the leaderboard.
///
/// Everything here is server-authoritative on purpose: XP is what the leaderboard
/// ranks on, so the client asks for an award and is told the result rather than
/// computing one. Mirrors the `/api/gamification/*` routes the web calls.
class GamificationRepository {
  GamificationRepository({
    required ApiClient api,
    FirebaseFirestore? firestore,
  })  : _api = api,
        _db = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirebaseFirestore _db;

  /// Awards XP for [action] — `watch_lesson`, `join_live`, `daily_streak`, …
  ///
  /// Throws on failure; callers that treat XP as best-effort should swallow it.
  /// The award is idempotent per action on the backend, not here.
  Future<XpResult> awardXp(String action, {Map<String, dynamic>? meta}) async {
    final data = await _api.post('/gamification/xp', {
      'action': action,
      'meta': meta ?? const <String, dynamic>{},
    });
    return XpResult.fromJson(data);
  }

  /// Records a finished sitting and awards XP for it in one call.
  ///
  /// [score] is a percentage; the backend adds a bonus at 90% or better.
  Future<XpResult> recordCbtSession({
    required String subject,
    required String exam,
    required num score,
    required int correct,
    required int total,
    String? topic,
  }) async {
    final data = await _api.post('/gamification/cbt-session', {
      'subject': subject,
      'exam': exam,
      'score': score,
      'correct': correct,
      'total': total,
      if (topic != null && topic.isNotEmpty) 'topic': topic,
    });
    return XpResult.fromJson(data);
  }

  /// The top [limit] students by XP.
  ///
  /// Falls back to reading `users` straight from Firestore when the backend is
  /// unreachable — Render's free tier sleeps, and an empty honour roll would
  /// read as "nobody has studied" rather than "we couldn't ask".
  Future<List<LeaderboardEntry>> leaderboard({int limit = 50}) async {
    try {
      final data = await _api.get(
        '/gamification/leaderboard',
        query: {'limit': '$limit'},
      );
      final rows = (data['leaderboard'] as List?) ?? const [];
      return rows
          .whereType<Map<String, dynamic>>()
          .map(LeaderboardEntry.fromJson)
          .toList();
    } catch (_) {
      return _leaderboardFromFirestore(limit);
    }
  }

  /// Ordered read first; if the composite index is missing, take a page and sort
  /// on the client. Both paths exist on the web for the same reason.
  Future<List<LeaderboardEntry>> _leaderboardFromFirestore(int limit) async {
    try {
      final snap = await _db
          .collection('users')
          .orderBy('xp', descending: true)
          .limit(limit)
          .get();
      return _rank(snap.docs);
    } catch (_) {
      try {
        final snap = await _db.collection('users').limit(200).get();
        final sorted = snap.docs.toList()
          ..sort((a, b) {
            final ax = a.data()['xp'];
            final bx = b.data()['xp'];
            return ((bx is num ? bx.toInt() : 0))
                .compareTo(ax is num ? ax.toInt() : 0);
          });
        return _rank(sorted.take(limit).toList());
      } catch (_) {
        return const [];
      }
    }
  }

  List<LeaderboardEntry> _rank(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      [
        for (var i = 0; i < docs.length; i++)
          LeaderboardEntry.fromJson(
            {...docs[i].data(), 'uid': docs[i].id},
            rank: i + 1,
          ),
      ];

  /// The signed-in student's rank and authoritative XP.
  Future<MyRank> myRank() async {
    final data = await _api.get('/gamification/rank');
    return MyRank.fromJson(data);
  }

  /// This week's race — the top students by XP earned since Monday.
  ///
  /// Weekly XP resets lazily, inside the award itself, so this can only come from
  /// the backend: it filters on the current week before ordering, which a client
  /// query has no cheap way to do. Returns empty on failure — a quiet board reads
  /// as a quiet week, which is the least misleading failure here.
  Future<WeeklyRace> weeklyRace({int limit = 5}) async {
    try {
      final data = await _api.get(
        '/gamification/leaderboard/weekly',
        query: {'limit': '$limit'},
      );
      final rows = (data['leaderboard'] as List?) ?? const [];
      return WeeklyRace(
        entries: rows
            .whereType<Map<String, dynamic>>()
            .map(LeaderboardEntry.fromJson)
            .toList(),
        myRank: data['myRank'] is num ? (data['myRank'] as num).toInt() : null,
      );
    } catch (_) {
      return const WeeklyRace(entries: [], myRank: null);
    }
  }
}

/// The weekly board, plus where this student sits on it.
class WeeklyRace {
  const WeeklyRace({required this.entries, this.myRank});

  final List<LeaderboardEntry> entries;

  /// Null when the student has earned nothing this week.
  final int? myRank;

  bool get isEmpty => entries.isEmpty;

  /// Monday 00:00 UTC, when the board resets.
  static DateTime nextReset([DateTime? now]) {
    final local = now ?? DateTime.now();
    final daysAhead = local.weekday == 7 ? 1 : 8 - local.weekday;
    final monday = DateTime(local.year, local.month, local.day)
        .add(Duration(days: daysAhead));
    return monday;
  }
}
