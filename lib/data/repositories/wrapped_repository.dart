import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/exam_attempt.dart';
import '../../domain/models/exam_result.dart';
import '../../domain/models/wrapped_stats.dart';
import 'attempt_repository.dart';

/// Everything a student's recap needs, loaded once and sliced per month.
///
/// Held rather than refetched because the month arrows are the whole point of
/// the screen — going back to August and forward again should not cost two
/// round trips.
class WrappedReport {
  WrappedReport({
    required this.results,
    required this.attempts,
    required this.streak,
    required this.xp,
    required this.isOfflineFallback,
  });

  final List<ExamResult> results;
  final List<ExamAttempt> attempts;
  final int streak;
  final int xp;

  /// True when the server's history could not be read and this is built from
  /// what happened on this phone. The screen says so rather than presenting a
  /// half month as the whole one.
  final bool isOfflineFallback;

  /// Months with at least one finished sitting, newest first.
  List<DateTime> get months {
    final seen = <String, DateTime>{};
    for (final r in results) {
      final at = r.submittedAt;
      if (at == null) continue;
      final month = DateTime(at.year, at.month);
      seen['${at.year}-${at.month}'] = month;
    }
    final list = seen.values.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// Which month to open on.
  ///
  /// Last month wins when it has anything in it: a recap is a look back, and
  /// for most of any given month the finished month is the more interesting
  /// one. Only once last month is empty does this fall to whatever is newest.
  DateTime get defaultMonth {
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1);
    final available = months;

    final hasPrevious = available.any(
      (m) => m.year == previous.year && m.month == previous.month,
    );
    if (hasPrevious) return previous;

    return available.isEmpty ? DateTime(now.year, now.month) : available.first;
  }

  WrappedStats forMonth(DateTime month) => WrappedStats.from(
        month: month,
        results: results,
        attempts: attempts,
        streak: streak,
        xp: xp,
      );
}

/// Assembles the monthly recap.
class WrappedRepository {
  WrappedRepository({
    required AttemptRepository attempts,
    FirebaseFirestore? firestore,
  })  : _attempts = attempts,
        _db = firestore ?? FirebaseFirestore.instance;

  final AttemptRepository _attempts;
  final FirebaseFirestore _db;

  /// How far back a recap can look. Twelve months of sittings is more than any
  /// student will scroll through and still one query.
  static const _window = Duration(days: 365);

  Future<WrappedReport> load({
    required String uid,
    required int streak,
    required int xp,
  }) async {
    // Local first: it is instant, it works offline, and it is the only source
    // that knows how long a sitting took.
    final attempts = await _attempts.recent(limit: 1000);

    final since = DateTime.now().subtract(_window);
    List<ExamResult>? results;
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('results')
          .where('submittedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .orderBy('submittedAt', descending: true)
          .get();
      results = snap.docs
          .map((d) => ExamResult.fromJson(d.id, d.data()))
          .toList(growable: false);
    } catch (_) {
      // Offline, or the read was refused. Fall through to the local rows.
    }

    if (results == null) {
      return WrappedReport(
        results: attempts.map(_asResult).toList(growable: false),
        attempts: attempts,
        streak: streak,
        xp: xp,
        isOfflineFallback: true,
      );
    }

    return WrappedReport(
      results: results,
      attempts: attempts,
      streak: streak,
      xp: xp,
      isOfflineFallback: false,
    );
  }

  /// A local attempt seen as a server result, for the offline recap.
  ///
  /// Every field the recap reads is present on both, so the fallback is a
  /// straight rename rather than an approximation.
  static ExamResult _asResult(ExamAttempt a) => ExamResult(
        id: a.id,
        subject: a.subject,
        correct: a.correct,
        total: a.total,
        exam: a.exam,
        topic: a.topic,
        submittedAt: a.submittedAt,
      );
}
