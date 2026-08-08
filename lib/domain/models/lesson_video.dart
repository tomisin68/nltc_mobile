import 'package:flutter/material.dart';

import 'app_user.dart' show tsToMs;

/// A senior class shelf — the first step of the lesson walk.
enum ClassLevel {
  sss1('sss1', 'SSS 1', Icons.spa_rounded, Color(0xFF16B364)),
  sss2('sss2', 'SSS 2', Icons.eco_rounded, Color(0xFF2E90FA)),
  sss3('sss3', 'SSS 3', Icons.park_rounded, Color(0xFF7A5AF8));

  const ClassLevel(this.wireName, this.label, this.icon, this.color);

  /// The value stored in `videos/{id}.classLevels[]`.
  final String wireName;
  final String label;
  final IconData icon;
  final Color color;

  static ClassLevel? byWireName(String name) {
    final needle = name.toLowerCase().trim();
    for (final level in values) {
      if (level.wireName == needle) return level;
    }
    return null;
  }
}

/// The topic a lesson with no tag is filed under, so nothing is unreachable.
const kUntaggedTopic = 'General';

/// A lesson video from the `videos` collection.
///
/// Filed under three things the student browses by: the classes it is meant for,
/// a subject, and a topic copied from the question bank.
class LessonVideo {
  const LessonVideo({
    required this.id,
    required this.title,
    this.subject,
    this.topic,
    this.classLevels = const {},
    this.teacher,
    this.description,
    this.url,
    this.thumbnail,
    this.duration,
    this.access = 'free',
    this.createdAt,
  });

  final String id;
  final String title;
  final String? subject;

  /// A question-bank topic tag. Null on lessons an admin never filed.
  final String? topic;

  /// Which SSS shelves this lesson sits on. Empty means every one — the field
  /// arrived after the first uploads, and a legacy lesson should stay visible
  /// rather than vanish. Same forgiving default as the web's `videoClassKeys`.
  final Set<ClassLevel> classLevels;

  /// The YouTube expert behind the lesson, credited on the card and the player.
  final String? teacher;

  final String? description;
  final String? url;
  final String? thumbnail;

  /// Free-text as the admin typed it — "12:40", "18 min". Shown, never parsed.
  final String? duration;

  /// `free` or `pro`. Anything other than `free` needs an active grant.
  final String access;

  final DateTime? createdAt;

  bool get isPro => access != 'free';

  /// The topic shelf this lesson belongs on.
  String get topicOrDefault {
    final tag = topic?.trim();
    return tag == null || tag.isEmpty ? kUntaggedTopic : tag;
  }

  /// Is this lesson on [level]'s shelf? An unfiled lesson is on all of them.
  bool matchesClass(ClassLevel? level) =>
      level == null || classLevels.isEmpty || classLevels.contains(level);

  /// Free-text match across everything a student might type — topic first,
  /// since searching by topic is what the box is for.
  bool matchesSearch(String needle) {
    final query = needle.trim().toLowerCase();
    if (query.isEmpty) return true;
    for (final field in [topic, title, subject, teacher, description]) {
      if (field != null && field.toLowerCase().contains(query)) return true;
    }
    return false;
  }

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

  static Set<ClassLevel> _levels(dynamic v) {
    if (v is! List) return const {};
    return {
      for (final entry in v)
        if (entry is String) ?ClassLevel.byWireName(entry),
    };
  }

  factory LessonVideo.fromJson(String id, Map<String, dynamic> json) {
    final ms = tsToMs(json['createdAt']);
    return LessonVideo(
      id: id,
      title: _str(json['title']) ?? 'Untitled lesson',
      subject: _str(json['subject']),
      topic: _str(json['topic']),
      classLevels: _levels(json['classLevels']),
      teacher: _str(json['teacher']),
      description: _str(json['description']),
      // The admin uploader writes `url`; older rows used `videoUrl`, which the
      // web's edit form still reads back.
      url: _str(json['url']) ?? _str(json['videoUrl']),
      thumbnail: _str(json['thumbnail']),
      duration: _str(json['duration']),
      access: _str(json['access']) ?? 'free',
      createdAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }
}
