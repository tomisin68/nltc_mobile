import '../../../data/repositories/gamification_repository.dart';
import '../../../domain/models/xp_result.dart';
import '../toast.dart';
import 'session_controller.dart';

/// Awards XP and tells the student about it.
///
/// Combines the web's `useAwardXP` hook with `handleXPResult` from
/// `src/utils/xpToast.js`: fire the award, patch the local profile so the XP bar
/// moves immediately, and raise the level-up / streak / achievement toasts.
///
/// Every award is best-effort. XP is a reward for work already done — if the
/// network drops on the way, the student keeps the result of their test and
/// simply doesn't see a toast. Nothing here may throw into a caller.
class XpService {
  XpService({
    required GamificationRepository gamification,
    required SessionController session,
  })  : _gamification = gamification,
        _session = session;

  final GamificationRepository _gamification;
  final SessionController _session;

  /// Awards XP for [action] and shows the resulting toasts.
  Future<void> award(String action, {Map<String, dynamic>? meta}) async {
    try {
      final result = await _gamification.awardXp(action, meta: meta);
      handle(result);
    } catch (_) {
      // Deliberately silent — see the class comment.
    }
  }

  /// Records a finished sitting, awarding XP for it.
  ///
  /// Returns the result so a results screen can show the XP it earned, or null
  /// if the call failed.
  Future<XpResult?> recordSession({
    required String subject,
    required String exam,
    required num score,
    required int correct,
    required int total,
    String? topic,
  }) async {
    try {
      final result = await _gamification.recordCbtSession(
        subject: subject,
        exam: exam,
        score: score,
        correct: correct,
        total: total,
        topic: topic,
      );
      handle(result);
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Applies an [XpResult] the caller already has.
  ///
  /// Toast order matters and follows the web: a level-up replaces the plain XP
  /// toast rather than stacking with it, because two toasts about the same award
  /// read as two awards.
  void handle(XpResult result) {
    if (result.leveledUp && result.level != null) {
      final name = result.level! >= 1 && result.level! <= 7
          ? _levelNames[result.level! - 1]
          : 'Level ${result.level}';
      showToast(
        'Level Up! You reached $name (Level ${result.level})!',
        variant: ToastVariant.success,
      );
    } else if (result.xpEarned > 0) {
      showToast('+${result.xpEarned} XP earned!',
          variant: ToastVariant.success);
    }

    if (result.streakBonusAwarded && (result.newStreak ?? 0) > 1) {
      showToast(
        '${result.newStreak}-day streak! +50 bonus XP',
        variant: ToastVariant.info,
      );
    }

    for (final id in result.newAchievements) {
      final label = Achievements.labels[id];
      if (label != null) {
        showToast('Achievement unlocked: $label!',
            variant: ToastVariant.success);
      }
    }

    _session.applyXpResult(result);
  }

  static const _levelNames = [
    'Starter',
    'Scholar',
    'Explorer',
    'Achiever',
    'Champion',
    'Elite',
    'Legend',
  ];
}
