import 'app_user.dart' show tsToMs;

/// One entry in the student's notification inbox.
///
/// The same record arrives through two doors: the backend's
/// `GET /api/notifications/me` (a mirror of `users/{uid}/notifications`) and an
/// FCM push landing while the app is open. Both are normalised here and stored
/// in the local `notifications` table, so the inbox opens instantly and still
/// reads correctly with no signal.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.category,
    this.route,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;

  /// The backend's `type` field — `announcement`, `chat_message`, and so on.
  /// Drives the icon, nothing else.
  final String? category;

  /// Deep link the backend attached, if any. Web routes (`/student.html`) mean
  /// nothing to the app, so this is only shown, never followed blindly.
  final String? route;

  final DateTime createdAt;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        category: category,
        route: route,
        read: read ?? this.read,
      );

  static String _str(dynamic v) => v == null ? '' : '$v'.trim();

  /// From `GET /api/notifications/me`, where `createdAt` is an ISO string and
  /// the deep link is buried in `data.url`.
  factory AppNotification.fromApi(Map<String, dynamic> m) {
    final data = m['data'];
    return AppNotification(
      id: _str(m['id']),
      title: _str(m['title']).isEmpty ? 'Notification' : _str(m['title']),
      body: _str(m['body']),
      category: _str(m['type']).isEmpty ? null : _str(m['type']),
      route: data is Map ? (_str(data['url']).isEmpty ? null : _str(data['url'])) : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        tsToMs(m['createdAt']) ?? DateTime.now().millisecondsSinceEpoch,
      ),
      read: m['read'] == true,
    );
  }

  /// From an FCM payload. Push messages carry no document id, so the message id
  /// (or the arrival time) stands in — enough to keep the row unique without
  /// duplicating an entry the next refresh will bring down properly.
  factory AppNotification.fromPush({
    required String id,
    String? title,
    String? body,
    Map<String, dynamic> data = const {},
  }) =>
      AppNotification(
        id: id,
        title: (title ?? '').trim().isEmpty ? 'NLTC Online' : title!.trim(),
        body: (body ?? '').trim(),
        category: _str(data['type']).isEmpty ? null : _str(data['type']),
        route: _str(data['url']).isEmpty ? null : _str(data['url']),
        createdAt: DateTime.now(),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'body': body,
        'category': category,
        'route': route,
        'created_at': createdAt.millisecondsSinceEpoch,
        'read': read ? 1 : 0,
      };

  factory AppNotification.fromRow(Map<String, Object?> r) => AppNotification(
        id: r['id'] as String,
        title: r['title'] as String? ?? '',
        body: r['body'] as String? ?? '',
        category: r['category'] as String?,
        route: r['route'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (r['created_at'] as num?)?.toInt() ?? 0,
        ),
        read: (r['read'] as num?)?.toInt() == 1,
      );
}
