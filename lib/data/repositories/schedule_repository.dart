import '../services/api_client.dart';

/// A class on the timetable, ahead of it happening.
class ScheduledClass {
  const ScheduledClass({
    required this.id,
    required this.title,
    this.subject,
    this.tutorName,
    this.scheduledAt,
  });

  final String id;
  final String title;
  final String? subject;
  final String? tutorName;
  final DateTime? scheduledAt;

  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  factory ScheduledClass.fromJson(Map<String, dynamic> json) => ScheduledClass(
        id: (json['id'] ?? '').toString(),
        title: _str(json['title']) ?? 'Class',
        subject: _str(json['subject']),
        tutorName: _str(json['tutorName']) ?? _str(json['hostName']),
        // The route serialises this as an ISO string, not a Firestore timestamp.
        scheduledAt: DateTime.tryParse('${json['scheduledAt']}'),
      );
}

/// The upcoming timetable.
class ScheduleRepository {
  const ScheduleRepository({required ApiClient api}) : _api = api;

  final ApiClient _api;

  /// The next [limit] classes, soonest first.
  ///
  /// Returns empty rather than throwing: the dashboard card that reads this
  /// hides itself when there is nothing, and a sleeping backend should not put an
  /// error on a student's home screen.
  Future<List<ScheduledClass>> upcoming({int limit = 3}) async {
    try {
      final data = await _api.get('/schedule', query: {'limit': '$limit'});
      final rows = (data['classes'] as List?) ?? const [];
      return rows
          .whereType<Map<String, dynamic>>()
          .map(ScheduledClass.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
