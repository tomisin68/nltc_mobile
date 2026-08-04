import 'dart:math';

import '../../domain/models/exam_attempt.dart';
import '../../domain/models/question.dart';
import '../services/api_client.dart';
import '../services/local_database.dart';

/// What happened to an attempt the moment it was submitted.
///
/// The score is never in doubt — grading is local — so this only reports how
/// the *server* leg went, which is what decides whether XP has landed yet.
class SubmitResult {
  const SubmitResult({required this.attempt, this.xpEarned, this.newXp});

  final ExamAttempt attempt;

  /// Only present once the backend has accepted the attempt.
  final int? xpEarned;
  final int? newXp;

  bool get synced => attempt.syncState == SyncState.synced;
}

/// Stores finished CBT attempts and gets them to the backend.
///
/// Grading happens on-device (see [ExamAttempt.grade]) so a student with no
/// signal still sees their score immediately. The attempt is written to SQLite
/// *before* any network call, which is what makes a failed submission a delay
/// rather than a lost result.
class AttemptRepository {
  AttemptRepository({required ApiClient api, required LocalDatabase local})
      : _api = api,
        _local = local;

  final ApiClient _api;
  final LocalDatabase _local;

  static final _random = Random();

  /// Give up on the server after this many rejections and mark the attempt
  /// `failed`. It stays on the device and still counts in the student's own
  /// history — it just stops burning requests on something the server refuses.
  static const maxSyncAttempts = 5;

  /// Client-side id, doubling as the idempotency key we send with the attempt.
  static String newAttemptId() {
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final salt = _random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
    return '$stamp-$salt';
  }

  Future<List<ExamAttempt>> recent({int limit = 30}) =>
      _local.recentAttempts(limit: limit);

  Future<int> unsyncedCount() => _local.unsyncedCount();

  /// Grades, saves, then tries to sync — in that order, always.
  Future<SubmitResult> submit({
    required String subject,
    required String exam,
    String? topic,
    required List<Question> questions,
    required Map<String, String> answers,
    required int durationSeconds,
  }) async {
    final attempt = ExamAttempt.grade(
      id: newAttemptId(),
      subject: subject,
      exam: exam,
      topic: topic,
      questions: questions,
      answers: answers,
      durationSeconds: durationSeconds,
    );

    await _local.saveAttempt(attempt);
    return _push(attempt);
  }

  /// Walks the queue oldest-first and returns how many made it across.
  ///
  /// Called on app start and when the student pulls to refresh, so a sitting
  /// taken on the bus syncs itself the next time there's signal.
  Future<int> syncPending() async {
    final pending = await _local.unsyncedAttempts();
    var synced = 0;
    for (final attempt in pending) {
      if (attempt.syncAttempts >= maxSyncAttempts) continue;
      final result = await _push(attempt);
      if (result.synced) {
        synced++;
      } else if (result.attempt.syncState == SyncState.pending) {
        // Still offline — the rest of the queue will fail the same way.
        break;
      }
    }
    return synced;
  }

  /// One trip to `/api/gamification/cbt-session`.
  ///
  /// An empty attempt is never sent: the route requires `total >= 1`, so a
  /// zero-question sitting would be rejected forever.
  Future<SubmitResult> _push(ExamAttempt attempt) async {
    if (attempt.total < 1) {
      await _local.markAttemptSync(attempt.id, SyncState.failed);
      return SubmitResult(attempt: attempt.copyWith(syncState: SyncState.failed));
    }

    final tries = attempt.syncAttempts + 1;
    try {
      final data = await _api.post(
        '/gamification/cbt-session',
        attempt.toSyncPayload(),
      );
      await _local.markAttemptSync(
        attempt.id,
        SyncState.synced,
        syncAttempts: tries,
      );
      return SubmitResult(
        attempt: attempt.copyWith(
          syncState: SyncState.synced,
          syncAttempts: tries,
        ),
        xpEarned: (data['xpEarned'] as num?)?.toInt(),
        newXp: (data['newXP'] as num?)?.toInt(),
      );
    } on ApiException catch (e) {
      // Offline means "not yet", not "no". Leave it pending and don't count the
      // try, or a week on a bad network would exhaust the retry budget.
      final rejected = !e.isOffline && (e.statusCode ?? 0) >= 400;
      final state = rejected && tries >= maxSyncAttempts
          ? SyncState.failed
          : SyncState.pending;

      await _local.markAttemptSync(
        attempt.id,
        state,
        syncAttempts: e.isOffline ? attempt.syncAttempts : tries,
      );
      return SubmitResult(
        attempt: attempt.copyWith(
          syncState: state,
          syncAttempts: e.isOffline ? attempt.syncAttempts : tries,
        ),
      );
    }
  }
}
