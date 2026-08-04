import 'app_user.dart' show tsToMs;

/// An announcement pinned by a tutor.
///
/// From `GET /api/broadcasts`, which serves the `broadcasts` collection with
/// `createdAt` already flattened to an ISO string.
class Broadcast {
  const Broadcast({
    required this.id,
    required this.title,
    required this.message,
    this.sentTo,
    this.audience,
    this.imageUrl,
    this.createdAt,
  });

  final String id;
  final String title;
  final String message;

  /// The admin's own label for who it went to — "All Users", "Pro Users Only".
  /// Shown as a badge when it is narrower than everyone.
  final String? sentTo;

  /// Junior/senior targeting: `all`, `bece` or `regular`.
  ///
  /// Note the create endpoint does not currently write this field, so in practice
  /// it is almost always absent and everything shows to everyone. Honoured anyway,
  /// so admin tooling that starts setting it works without an app release.
  final String? audience;

  final String? imageUrl;
  final DateTime? createdAt;

  /// Whether this should be shown to a student on the junior track.
  bool visibleTo({required bool isJunior}) => switch (audience ?? 'all') {
        'bece' => isJunior,
        'regular' => !isJunior,
        _ => true,
      };

  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  factory Broadcast.fromJson(Map<String, dynamic> json) {
    final ms = tsToMs(json['createdAt']);
    return Broadcast(
      id: _str(json['id']) ?? '',
      title: _str(json['title']) ?? 'Announcement',
      message: _str(json['message']) ?? _str(json['body']) ?? '',
      sentTo: _str(json['sentTo']),
      audience: _str(json['audience']),
      imageUrl: _str(json['imageUrl']),
      createdAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }
}
