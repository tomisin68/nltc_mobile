import 'app_user.dart' show tsToMs;

/// A lesson video from the `videos` collection.
class LessonVideo {
  const LessonVideo({
    required this.id,
    required this.title,
    this.subject,
    this.url,
    this.thumbnail,
    this.duration,
    this.access = 'free',
    this.createdAt,
  });

  final String id;
  final String title;
  final String? subject;
  final String? url;
  final String? thumbnail;

  /// Free-text as the admin typed it — "12:40", "18 min". Shown, never parsed.
  final String? duration;

  /// `free` or `pro`. Anything other than `free` needs an active grant.
  final String access;

  final DateTime? createdAt;

  bool get isPro => access != 'free';

  /// The YouTube id when [url] is a YouTube link, else null.
  ///
  /// Admins paste whatever the share button gave them, so all three shapes have
  /// to work: `watch?v=`, `youtu.be/` and `embed/`.
  String? get youTubeId {
    final link = url;
    if (link == null) return null;
    final match = RegExp(
      r'(?:youtube\.com/(?:watch\?v=|embed/)|youtu\.be/)([a-zA-Z0-9_-]{11})',
    ).firstMatch(link);
    return match?.group(1);
  }

  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  factory LessonVideo.fromJson(String id, Map<String, dynamic> json) {
    final ms = tsToMs(json['createdAt']);
    return LessonVideo(
      id: id,
      title: _str(json['title']) ?? 'Untitled lesson',
      subject: _str(json['subject']),
      url: _str(json['url']),
      thumbnail: _str(json['thumbnail']),
      duration: _str(json['duration']),
      access: _str(json['access']) ?? 'free',
      createdAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }
}
