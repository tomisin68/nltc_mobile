/// What the backend returns after awarding XP.
///
/// Shape comes from `POST /api/gamification/xp` and
/// `POST /api/gamification/cbt-session`, which both answer with this — see
/// `handleXPResult` in `src/utils/xpToast.js`.
class XpResult {
  const XpResult({
    this.xpEarned = 0,
    this.newXp,
    this.newStreak,
    this.newCbtCount,
    this.streakBonusAwarded = false,
    this.leveledUp = false,
    this.level,
    this.newAchievements = const [],
  });

  final int xpEarned;

  /// The authoritative XP total after the award. Null when the backend didn't
  /// say — in which case the local total is left alone rather than guessed at.
  final int? newXp;

  final int? newStreak;
  final int? newCbtCount;
  final bool streakBonusAwarded;
  final bool leveledUp;
  final int? level;

  /// Achievement ids unlocked by this award, for the "Achievement unlocked"
  /// toasts.
  final List<String> newAchievements;

  static int? _int(dynamic v) => v is num ? v.toInt() : null;

  factory XpResult.fromJson(Map<String, dynamic> json) => XpResult(
        xpEarned: _int(json['xpEarned']) ?? 0,
        newXp: _int(json['newXP']) ?? _int(json['newXp']),
        newStreak: _int(json['newStreak']),
        newCbtCount: _int(json['newCbtCount']),
        streakBonusAwarded: json['streakBonusAwarded'] == true,
        leveledUp: json['leveledUp'] == true,
        level: _int(json['level']),
        newAchievements: (json['newAchievements'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

/// Human labels for the achievement ids the backend can unlock.
///
/// Mirrors `ACHIEVEMENT_LABELS` in `src/utils/xpToast.js`. An id with no label
/// here is skipped rather than shown raw — a toast reading "xp_9000" is worse
/// than no toast.
abstract final class Achievements {
  static const labels = <String, String>{
    'first_lesson': '🎬 First Lesson',
    'streak_3': '🔥 3-Day Streak',
    'streak_7': '⚡ 7-Day Streak',
    'cbt_5': '📝 CBT Starter',
    'cbt_10': '🧠 CBT Master',
    'xp_500': '⭐ 500 XP',
    'xp_1000': '💫 1,000 XP',
    'top_10': '🏆 Top 10',
    'top_50': '🎖️ Top 50',
  };
}
