/// Normalises the many timestamp shapes that reach the client into epoch millis.
///
/// Firestore hands back a `Timestamp` (which exposes `toDate()`), cached JSON
/// hands back an `int`, and hand-written admin data sometimes holds an ISO
/// string or a `{seconds}` map. Duck-typing rather than importing
/// `cloud_firestore` keeps this model free of Firebase types.
int? tsToMs(dynamic ts) {
  if (ts == null) return null;
  if (ts is int) return ts;
  if (ts is DateTime) return ts.millisecondsSinceEpoch;

  try {
    final dynamic d = ts;
    // Firestore Timestamp
    if (d.toDate != null) {
      final date = d.toDate();
      if (date is DateTime) return date.millisecondsSinceEpoch;
    }
  } catch (_) {
    // Not a Timestamp — fall through to the remaining shapes.
  }

  if (ts is Map && ts['seconds'] is num) {
    return (ts['seconds'] as num).toInt() * 1000;
  }
  if (ts is String) return DateTime.tryParse(ts)?.millisecondsSinceEpoch;
  if (ts is num) return ts.toInt();
  return null;
}

/// The daily mission set (`users/{uid}.dailyMission`).
///
/// Three tasks a day, seeded from the date so every student on a given day gets
/// the same three — the web's `getDailyTaskIds`.
class DailyMission {
  const DailyMission({
    required this.date,
    required this.taskIds,
    required this.completed,
  });

  /// `yyyy-MM-dd` in local time. A mission whose date isn't today is stale.
  final String date;
  final List<String> taskIds;
  final List<String> completed;

  static List<String> _strings(dynamic v) => v is List
      ? v.whereType<String>().toList(growable: false)
      : const <String>[];

  factory DailyMission.fromMap(Map<String, dynamic> m) => DailyMission(
        date: (m['date'] ?? '').toString(),
        taskIds: _strings(m['taskIds']),
        completed: _strings(m['completed']),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'taskIds': taskIds,
        'completed': completed,
      };
}

/// The student's profile document (`users/{uid}`).
///
/// Cached to disk on every refresh so a cold start with no network still knows
/// who the student is and whether their account is active.
class AppUser {
  const AppUser({
    required this.uid,
    this.email,
    this.firstName,
    this.lastName,
    this.phone,
    this.photoUrl,
    this.profileImage,
    this.gender,
    this.dateOfBirth,
    this.houseAddress,
    this.parentName,
    this.parentPhone,
    this.parentEmail,
    this.center,
    this.classId,
    this.className,
    this.classType,
    this.role = 'student',
    this.plan,
    this.studentMode = 'online',
    this.targetExam,
    this.state,
    this.xp = 0,
    this.streak = 0,
    this.cbtCount = 0,
    this.totalCorrect = 0,
    this.weeklyGoal = 5,
    this.weeklyXp = 0,
    this.weekStart,
    this.achievements = const [],
    this.dailyMission,
    this.createdAt,
    this.examName,
    this.examDate,
    this.trialEndsAt,
    this.planExpiresAt,
    this.planActivatedAt,
    this.lessonFeePaid = false,
    this.lessonFeeExpiresAt,
    this.lessonFeePaidAt,
  });

  final String uid;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? photoUrl;

  /// The Cloudinary avatar the student uploaded on the profile screen. Distinct
  /// from [photoUrl], which is whatever the auth provider supplied.
  final String? profileImage;

  final String? gender;

  /// `yyyy-MM-dd`, stored as typed rather than as a timestamp — the web keeps it
  /// as the raw value of a `<input type="date">`.
  final String? dateOfBirth;

  final String? houseAddress;
  final String? parentName;
  final String? parentPhone;

  /// Where the weekly progress report is sent.
  final String? parentEmail;

  /// The physical centre this student attends, when [studentMode] is `physical`.
  final String? center;

  // The class (fee band) the student last chose to pay for.
  final String? classId;
  final String? className;
  final String? classType;

  final String role;
  final String? plan;

  /// `'online'` for every account the app creates — the app deliberately has
  /// no physical-centre signup path.
  final String studentMode;

  final String? targetExam;
  final String? state;

  final int xp;
  final int streak;
  final int cbtCount;
  final int totalCorrect;

  /// Practice sessions the student is aiming for this week — the dial on the
  /// dashboard. Student-editable, 1–21.
  final int weeklyGoal;

  /// XP earned since the backend's Monday reset. Only trustworthy while
  /// [weekStart] names the current UTC week — see [weeklyXpThisWeek].
  final int weeklyXp;

  /// `yyyy-MM-dd` of the UTC Monday [weeklyXp] belongs to.
  final String? weekStart;

  /// IDs of badges the backend has awarded outright.
  final List<String> achievements;

  final DailyMission? dailyMission;

  final int? createdAt;

  final String? examName;
  final int? examDate;

  // Access grants — all epoch millis.
  final int? trialEndsAt;
  final int? planExpiresAt;
  final int? planActivatedAt;
  final bool lessonFeePaid;
  final int? lessonFeeExpiresAt;
  final int? lessonFeePaidAt;

  String get displayName {
    final full = [firstName, lastName]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (full.isNotEmpty) return full;
    return email?.split('@').first ?? 'Student';
  }

  String get initials {
    final f = (firstName ?? '').trim();
    final l = (lastName ?? '').trim();
    if (f.isNotEmpty && l.isNotEmpty) return '${f[0]}${l[0]}'.toUpperCase();
    final source = displayName.trim();
    return source.isEmpty ? '?' : source[0].toUpperCase();
  }

  /// The avatar to show, preferring the one the student uploaded themselves.
  String? get avatarUrl => profileImage ?? photoUrl;

  /// True for the junior track. The web tests both spellings because the signup
  /// form and the admin console have historically written different ones.
  bool get isJunior =>
      targetExam == 'BECE (JSS)' || targetExam == 'Junior WAEC';

  /// The UTC Monday of the current week, as the backend writes it.
  static String utcWeekStart([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    final back = utc.weekday == 7 ? 6 : utc.weekday - 1;
    final monday = DateTime.utc(utc.year, utc.month, utc.day)
        .subtract(Duration(days: back));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}';
  }

  /// [weeklyXp], but zero once it belongs to a week that has already rolled
  /// over — the counter is only reset lazily, server-side.
  int get weeklyXpThisWeek => weekStart == utcWeekStart() ? weeklyXp : 0;

  /// Returns a copy with the gamification counters replaced.
  ///
  /// Only these fields: the backend owns XP, streak and CBT count, and it
  /// returns the authoritative values when it awards them. Patching them locally
  /// is what makes the sidebar's XP bar move the instant a test is submitted,
  /// instead of a beat later when the Firestore stream catches up. Nothing else
  /// on the profile is self-editable from here — `plan` and `role` are
  /// server-controlled and must only ever arrive over the stream.
  AppUser copyWithProgress({int? xp, int? streak, int? cbtCount}) => _copy(
        xp: xp,
        streak: streak,
        cbtCount: cbtCount,
      );

  /// Returns a copy with the fields the student themselves can edit replaced.
  ///
  /// Used for the optimistic patch after a profile save, so the form doesn't
  /// flash back to the old values while the Firestore write round-trips. The
  /// server-owned fields (`plan`, `role`, every access grant) are absent on
  /// purpose — those only ever arrive over the stream.
  AppUser copyWithProfile({
    String? firstName,
    String? lastName,
    String? phone,
    Object? profileImage = _unset,
    Object? gender = _unset,
    Object? dateOfBirth = _unset,
    Object? houseAddress = _unset,
    Object? parentName = _unset,
    Object? parentPhone = _unset,
    Object? parentEmail = _unset,
    Object? center = _unset,
    String? studentMode,
    Object? targetExam = _unset,
    String? state,
    int? weeklyGoal,
    Object? examName = _unset,
    Object? examDate = _unset,
    DailyMission? dailyMission,
  }) =>
      _copy(
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        profileImage: profileImage,
        gender: gender,
        dateOfBirth: dateOfBirth,
        houseAddress: houseAddress,
        parentName: parentName,
        parentPhone: parentPhone,
        parentEmail: parentEmail,
        center: center,
        studentMode: studentMode,
        targetExam: targetExam,
        state: state,
        weeklyGoal: weeklyGoal,
        examName: examName,
        examDate: examDate,
        dailyMission: dailyMission,
      );

  AppUser _copy({
    String? firstName,
    String? lastName,
    String? phone,
    Object? profileImage = _unset,
    Object? gender = _unset,
    Object? dateOfBirth = _unset,
    Object? houseAddress = _unset,
    Object? parentName = _unset,
    Object? parentPhone = _unset,
    Object? parentEmail = _unset,
    Object? center = _unset,
    String? studentMode,
    Object? targetExam = _unset,
    String? state,
    int? xp,
    int? streak,
    int? cbtCount,
    int? weeklyGoal,
    Object? examName = _unset,
    Object? examDate = _unset,
    DailyMission? dailyMission,
  }) =>
      AppUser(
        uid: uid,
        email: email,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        phone: phone ?? this.phone,
        photoUrl: photoUrl,
        profileImage: profileImage == _unset
            ? this.profileImage
            : profileImage as String?,
        gender: gender == _unset ? this.gender : gender as String?,
        dateOfBirth:
            dateOfBirth == _unset ? this.dateOfBirth : dateOfBirth as String?,
        houseAddress: houseAddress == _unset
            ? this.houseAddress
            : houseAddress as String?,
        parentName:
            parentName == _unset ? this.parentName : parentName as String?,
        parentPhone:
            parentPhone == _unset ? this.parentPhone : parentPhone as String?,
        parentEmail:
            parentEmail == _unset ? this.parentEmail : parentEmail as String?,
        center: center == _unset ? this.center : center as String?,
        classId: classId,
        className: className,
        classType: classType,
        role: role,
        plan: plan,
        studentMode: studentMode ?? this.studentMode,
        targetExam:
            targetExam == _unset ? this.targetExam : targetExam as String?,
        state: state ?? this.state,
        xp: xp ?? this.xp,
        streak: streak ?? this.streak,
        cbtCount: cbtCount ?? this.cbtCount,
        totalCorrect: totalCorrect,
        weeklyGoal: weeklyGoal ?? this.weeklyGoal,
        weeklyXp: weeklyXp,
        weekStart: weekStart,
        achievements: achievements,
        dailyMission: dailyMission ?? this.dailyMission,
        createdAt: createdAt,
        examName: examName == _unset ? this.examName : examName as String?,
        examDate: examDate == _unset ? this.examDate : examDate as int?,
        trialEndsAt: trialEndsAt,
        planExpiresAt: planExpiresAt,
        planActivatedAt: planActivatedAt,
        lessonFeePaid: lessonFeePaid,
        lessonFeeExpiresAt: lessonFeeExpiresAt,
        lessonFeePaidAt: lessonFeePaidAt,
      );

  /// Sentinel so the copy helpers can tell "leave it alone" from "set to null".
  static const _unset = Object();

  static int _int(dynamic v) => v is num ? v.toInt() : 0;
  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> m) => AppUser(
        uid: uid,
        email: _str(m['email']),
        firstName: _str(m['firstName']),
        lastName: _str(m['lastName']),
        phone: _str(m['phone']),
        photoUrl: _str(m['photoURL']) ?? _str(m['photoUrl']),
        profileImage: _str(m['profileImage']),
        gender: _str(m['gender']),
        dateOfBirth: _str(m['dateOfBirth']),
        houseAddress: _str(m['houseAddress']),
        parentName: _str(m['parentName']),
        parentPhone: _str(m['parentPhone']),
        parentEmail: _str(m['parentEmail']),
        center: _str(m['center']),
        classId: _str(m['classId']),
        className: _str(m['className']),
        classType: _str(m['classType']),
        role: _str(m['role']) ?? 'student',
        plan: _str(m['plan']),
        studentMode: _str(m['studentMode']) ?? 'online',
        targetExam: _str(m['targetExam']),
        state: _str(m['state']),
        xp: _int(m['xp']),
        streak: _int(m['streak']),
        cbtCount: _int(m['cbtCount']),
        totalCorrect: _int(m['totalCorrect']),
        // A record written before weekly goals existed reads as the web's
        // default of five rather than as zero, which would divide by nothing.
        weeklyGoal: m['weeklyGoal'] is num ? _int(m['weeklyGoal']) : 5,
        weeklyXp: _int(m['weeklyXp']),
        weekStart: _str(m['weekStart']),
        achievements: m['achievements'] is List
            ? (m['achievements'] as List).whereType<String>().toList()
            : const [],
        dailyMission: m['dailyMission'] is Map
            ? DailyMission.fromMap(
                Map<String, dynamic>.from(m['dailyMission'] as Map),
              )
            : null,
        createdAt: tsToMs(m['createdAt']),
        examName: _str(m['examName']),
        examDate: tsToMs(m['examDate']),
        trialEndsAt: tsToMs(m['trialEndsAt']),
        planExpiresAt: tsToMs(m['planExpiresAt']),
        planActivatedAt: tsToMs(m['planActivatedAt']),
        lessonFeePaid: m['lessonFeePaid'] == true,
        lessonFeeExpiresAt: tsToMs(m['lessonFeeExpiresAt']),
        lessonFeePaidAt: tsToMs(m['lessonFeePaidAt']),
      );

  /// Plain JSON for the on-device profile cache. Timestamps are already millis,
  /// so this round-trips through [AppUser.fromMap] unchanged.
  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'photoURL': photoUrl,
        'profileImage': profileImage,
        'gender': gender,
        'dateOfBirth': dateOfBirth,
        'houseAddress': houseAddress,
        'parentName': parentName,
        'parentPhone': parentPhone,
        'parentEmail': parentEmail,
        'center': center,
        'classId': classId,
        'className': className,
        'classType': classType,
        'role': role,
        'plan': plan,
        'studentMode': studentMode,
        'targetExam': targetExam,
        'state': state,
        'xp': xp,
        'streak': streak,
        'cbtCount': cbtCount,
        'totalCorrect': totalCorrect,
        'weeklyGoal': weeklyGoal,
        'weeklyXp': weeklyXp,
        'weekStart': weekStart,
        'achievements': achievements,
        'dailyMission': dailyMission?.toJson(),
        'createdAt': createdAt,
        'examName': examName,
        'examDate': examDate,
        'trialEndsAt': trialEndsAt,
        'planExpiresAt': planExpiresAt,
        'planActivatedAt': planActivatedAt,
        'lessonFeePaid': lessonFeePaid,
        'lessonFeeExpiresAt': lessonFeeExpiresAt,
        'lessonFeePaidAt': lessonFeePaidAt,
      };
}
