import 'gamification.dart';

/// One row on the honour roll.
///
/// Fed by `GET /api/gamification/leaderboard`, and by a direct Firestore read on
/// the `users` collection when the backend is unreachable — so every field has to
/// tolerate being absent.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.rank,
    required this.xp,
    this.firstName,
    this.lastName,
    this.email,
    this.targetExam,
    this.state,
    this.photoUrl,
    this.weeklyXp = 0,
  });

  final String uid;
  final int rank;
  final int xp;

  /// XP earned since Monday. Only the weekly board populates this.
  final int weeklyXp;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? targetExam;
  final String? state;
  final String? photoUrl;

  /// What the row shows as a name. Falls back through the email local part, so a
  /// student who never filled in their profile still reads as a person.
  String get displayName {
    final full = [firstName, lastName]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (full.isNotEmpty) return full;
    final local = email?.split('@').first;
    if (local != null && local.isNotEmpty) return local;
    return 'Student';
  }

  String get initial {
    final source = (firstName?.trim().isNotEmpty ?? false)
        ? firstName!
        : (email?.trim().isNotEmpty ?? false)
            ? email!
            : '?';
    return source[0].toUpperCase();
  }

  int get level => Levels.forXp(xp);
  String get levelName => Levels.nameForXp(xp);

  /// The web labels a blank target exam as JAMB, which is the default the signup
  /// form applies anyway.
  String get exam => targetExam ?? 'JAMB';

  static int _int(dynamic v) => v is num ? v.toInt() : 0;
  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json, {int? rank}) =>
      LeaderboardEntry(
        uid: _str(json['uid']) ?? _str(json['id']) ?? '',
        rank: rank ?? _int(json['rank']),
        xp: _int(json['xp']),
        firstName: _str(json['firstName']),
        lastName: _str(json['lastName']),
        email: _str(json['email']),
        targetExam: _str(json['targetExam']),
        state: _str(json['state']),
        photoUrl: _str(json['photoURL']) ?? _str(json['photoUrl']),
        weeklyXp: _int(json['weeklyXp']),
      );
}

/// The signed-in student's own standing, from `GET /api/gamification/rank`.
class MyRank {
  const MyRank({this.rank, this.xp, this.newAchievements = const []});

  final int? rank;

  /// Authoritative XP. The web overwrites its local copy with this, since the
  /// leaderboard read is the one place both numbers are computed together.
  final int? xp;

  final List<String> newAchievements;

  factory MyRank.fromJson(Map<String, dynamic> json) => MyRank(
        rank: json['rank'] is num ? (json['rank'] as num).toInt() : null,
        xp: json['xp'] is num ? (json['xp'] as num).toInt() : null,
        newAchievements: (json['newAchievements'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}
