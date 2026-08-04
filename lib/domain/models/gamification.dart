import 'app_user.dart';

/// XP → level mapping.
///
/// Direct port of `LEVEL_NAMES` / `xpToLevel` / `xpProgressInLevel` in the web
/// app's `src/contexts/AuthContext.jsx`. The thresholds also mirror
/// `nltc-backend/src/services/gamificationService.js` — all three must agree, or
/// the sidebar shows a level the backend never awarded.
abstract final class Levels {
  static const names = <String>[
    'Starter',
    'Scholar',
    'Explorer',
    'Achiever',
    'Champion',
    'Elite',
    'Legend',
  ];

  static const thresholds = <int>[0, 500, 1500, 3500, 7000, 12000, 20000];

  /// The level [xp] currently sits in, 1-based. Clamped to [names] length, so a
  /// student past the last threshold stays "Legend" rather than falling off.
  static int forXp(int xp) {
    var level = 0;
    for (var i = 0; i < thresholds.length; i++) {
      if (xp >= thresholds[i]) level = i + 1;
    }
    return level < names.length ? level : names.length;
  }

  static String nameForXp(int xp) => names[forXp(xp) - 1];

  /// How far through the current level [xp] is, 0..1. Returns 1 at max level.
  static double progressInLevel(int xp) {
    // The trailing sentinel is what the web uses to give the top level a
    // finite-width bar instead of dividing by zero.
    const ladder = <int>[0, 500, 1500, 3500, 7000, 12000, 20000, 999999];
    for (var i = 0; i < ladder.length - 1; i++) {
      if (xp < ladder[i + 1]) {
        return (xp - ladder[i]) / (ladder[i + 1] - ladder[i]);
      }
    }
    return 1;
  }

  /// The XP total that ends the current level — what the sidebar counts toward.
  static int nextLevelXp(int xp) {
    final level = forXp(xp);
    return level < thresholds.length ? thresholds[level] : 20000;
  }
}

/// Which counter on the profile an achievement measures.
enum AchievementMetric { xp, cbtCount, streak }

/// One badge, and how close this student is to it.
///
/// Port of `ALL_ACHIEVEMENTS` / `computeAchievements` in the web's `AuthContext`.
/// Two kinds live in the same list: those the client can derive from a counter
/// (`streak_7`, `xp_500`) and those only the backend can award (`first_lesson`,
/// `top_10`), which have no [metric] and are earned purely by appearing in the
/// profile's `achievements` array.
class Achievement {
  const Achievement({
    required this.id,
    required this.icon,
    required this.label,
    required this.description,
    this.metric,
    this.threshold,
    this.earned = false,
    this.progress = 0,
  });

  final String id;

  /// The emoji the web shows — kept as the medal glyph so the two match.
  final String icon;
  final String label;
  final String description;

  final AchievementMetric? metric;
  final int? threshold;

  final bool earned;

  /// 0..1.
  final double progress;

  static const all = <Achievement>[
    Achievement(
      id: 'first_lesson',
      icon: '🎬',
      label: 'First Lesson',
      description: 'Watch your first video',
    ),
    Achievement(
      id: 'streak_3',
      icon: '🔥',
      label: '3-Day Streak',
      description: 'Study 3 days in a row',
      metric: AchievementMetric.streak,
      threshold: 3,
    ),
    Achievement(
      id: 'streak_7',
      icon: '⚡',
      label: '7-Day Streak',
      description: 'Study 7 days in a row',
      metric: AchievementMetric.streak,
      threshold: 7,
    ),
    Achievement(
      id: 'cbt_5',
      icon: '📝',
      label: 'CBT Starter',
      description: 'Complete 5 CBT sessions',
      metric: AchievementMetric.cbtCount,
      threshold: 5,
    ),
    Achievement(
      id: 'cbt_10',
      icon: '🧠',
      label: 'CBT Master',
      description: 'Complete 10 CBT sessions',
      metric: AchievementMetric.cbtCount,
      threshold: 10,
    ),
    Achievement(
      id: 'xp_500',
      icon: '⭐',
      label: '500 XP',
      description: 'Earn 500 XP',
      metric: AchievementMetric.xp,
      threshold: 500,
    ),
    Achievement(
      id: 'xp_1000',
      icon: '💫',
      label: '1,000 XP',
      description: 'Earn 1,000 XP',
      metric: AchievementMetric.xp,
      threshold: 1000,
    ),
    Achievement(
      id: 'top_10',
      icon: '🏆',
      label: 'Top 10',
      description: 'Reach Top 10 nationwide',
    ),
    Achievement(
      id: 'top_50',
      icon: '🎖️',
      label: 'Top 50',
      description: 'Reach Top 50 nationwide',
    ),
  ];

  /// Every badge, scored against [profile].
  static List<Achievement> evaluate(AppUser? profile) {
    final awarded = profile?.achievements ?? const <String>[];

    return all.map((a) {
      var earned = awarded.contains(a.id);
      var progress = earned ? 1.0 : 0.0;

      final metric = a.metric;
      final threshold = a.threshold;
      if (!earned && metric != null && threshold != null && threshold > 0) {
        final value = switch (metric) {
          AchievementMetric.xp => profile?.xp ?? 0,
          AchievementMetric.cbtCount => profile?.cbtCount ?? 0,
          AchievementMetric.streak => profile?.streak ?? 0,
        };
        progress = (value / threshold).clamp(0.0, 1.0);
        // The counter having passed the bar is the award — the backend writes the
        // array a beat later, and the web takes the same shortcut so the badge
        // lights up the moment it's true.
        if (progress >= 1) earned = true;
      }

      return Achievement(
        id: a.id,
        icon: a.icon,
        label: a.label,
        description: a.description,
        metric: a.metric,
        threshold: a.threshold,
        earned: earned,
        progress: progress,
      );
    }).toList(growable: false);
  }
}
