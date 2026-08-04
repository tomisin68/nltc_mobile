import 'package:shared_preferences/shared_preferences.dart';

/// Records that a daily mission was genuinely completed today.
///
/// Port of `src/utils/missionSignals.js`. The dashboard's "Today's plan" reads
/// these to tick missions off, and they are deliberately kept out of Firestore:
/// a mission is a nudge, not a graded record, and writing one per tap would cost
/// a document write for something that resets every night.
///
/// Keys are scoped by both uid and date, which is what makes them reset at
/// midnight and stay separate for two students sharing a phone.
class MissionSignals {
  const MissionSignals(this._prefs);

  final SharedPreferences _prefs;

  static String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  static String _key(String taskId, String uid) =>
      'nltc_task_${taskId}_${uid}_${_todayKey()}';

  Future<void> set(String taskId, String? uid) async {
    if (uid == null || uid.isEmpty) return;
    await _prefs.setBool(_key(taskId, uid), true);
  }

  bool has(String taskId, String? uid) {
    if (uid == null || uid.isEmpty) return false;
    return _prefs.getBool(_key(taskId, uid)) ?? false;
  }
}
