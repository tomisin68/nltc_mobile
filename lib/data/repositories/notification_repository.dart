import '../../domain/models/app_notification.dart';
import '../services/api_client.dart';
import '../services/local_database.dart';

/// The notification inbox: local first, server second.
///
/// Every read goes to SQLite so the inbox opens with no spinner and no signal.
/// [refresh] pulls `GET /api/notifications/me` and mirrors it down; failures are
/// reported to the caller but never clear what is already on the device.
class NotificationRepository {
  NotificationRepository({required ApiClient api, required LocalDatabase local})
      : _api = api,
        _local = local;

  final ApiClient _api;
  final LocalDatabase _local;

  Future<List<AppNotification>> cached({int limit = 50}) async {
    final rows = await _local.notifications(limit: limit);
    return rows.map(AppNotification.fromRow).toList();
  }

  Future<int> unreadCount() => _local.unreadNotificationCount();

  /// Pulls the server's copy into the local table and returns the merged list.
  ///
  /// Throws [ApiException] on failure so the UI can say *why* nothing new
  /// arrived; the caller keeps showing [cached] either way.
  Future<List<AppNotification>> refresh() async {
    final data = await _api.get('/notifications/me');
    final raw = data['notifications'];
    if (raw is! List) return cached();

    final locallyRead = await _local.readNotificationIds();
    final rows = <Map<String, Object?>>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final notification = AppNotification.fromApi(
        Map<String, dynamic>.from(entry),
      );
      if (notification.id.isEmpty) continue;
      rows.add(
        notification
            .copyWith(read: notification.read || locallyRead.contains(notification.id))
            .toRow(),
      );
    }

    await _local.saveNotifications(rows);
    return cached();
  }

  /// Stores a push that landed while the app was open, so the inbox matches the
  /// tray without waiting for the next refresh.
  Future<void> record(AppNotification notification) =>
      _local.saveNotification(notification.toRow());

  /// Marks one as read. The device is updated first — the badge must clear the
  /// instant it's tapped, whether or not the server can be reached.
  Future<void> markRead(String id) async {
    await _local.markNotificationRead(id);
    try {
      await _api.post('/notifications/mark-read', {
        'notifIds': [id],
      });
    } on ApiException {
      // The local flag stands. Worst case the server still calls it unread and
      // the next refresh leaves it read anyway, thanks to the merge above.
    }
  }

  Future<void> markAllRead() async {
    await _local.markAllNotificationsRead();
    try {
      await _api.post('/notifications/mark-read', {'all': true});
    } on ApiException {
      // As above — local state is authoritative for the badge.
    }
  }

  /// Registers this device for push. Safe to call on every sign-in: the backend
  /// does an `arrayUnion`, so re-sending the same token is a no-op.
  Future<void> registerDevice(String token, String platform) =>
      _api.post('/notifications/register-token', {
        'fcmToken': token,
        'platform': platform,
      });
}
