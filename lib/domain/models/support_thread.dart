import 'package:flutter/material.dart';

import 'app_user.dart' show tsToMs;

/// What a student says their problem is about.
///
/// The ids are the contract with the website — the admin Support Inbox renders
/// `thread.topic` through its own label table, so a new id added here without
/// one added there shows up as "Support request".
enum SupportTopic {
  payment('payment', 'Payment & fees', Icons.payments_rounded),
  access('access', 'Account access', Icons.lock_rounded),
  lessons('lessons', 'Lessons & videos', Icons.play_circle_rounded),
  cbt('cbt', 'CBT & mock exams', Icons.laptop_mac_rounded),
  live('live', 'Live classes', Icons.sensors_rounded),
  technical('technical', 'Technical problem', Icons.bug_report_rounded),
  other('other', 'Something else', Icons.chat_bubble_rounded);

  const SupportTopic(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;

  /// The label for a stored id, including ids this build has never heard of.
  static String labelFor(String? id) {
    for (final topic in SupportTopic.values) {
      if (topic.id == id) return topic.label;
    }
    return 'Support request';
  }
}

/// Whether a support request is still waiting on somebody.
enum SupportStatus {
  open,
  resolved;

  static SupportStatus parse(String? raw) =>
      raw == 'resolved' ? SupportStatus.resolved : SupportStatus.open;
}

/// One help conversation — `supportThreads/{threadId}`.
///
/// A student may hold several: once a request is solved it stays solved and
/// moves into their history, and the next question opens a new one. Ownership
/// is the `uid` FIELD rather than the document id, which still lets a
/// locked-out account reach support — the rules check that field directly and
/// never read a profile the student may no longer be allowed to read.
///
/// Threads written before conversations could stack up have the uid as their
/// id *and* in the field, so they load here as that student's first chat.
class SupportThread {
  const SupportThread({
    required this.id,
    required this.uid,
    required this.status,
    this.topic,
    this.lastMessage,
    this.lastMessageFromAdmin = false,
    this.lastActivity,
    this.unreadForStudent = 0,
    this.unreadForAdmin = 0,
  });

  /// The document id — what the messages sub-collection hangs off.
  final String id;

  final String uid;
  final SupportStatus status;

  /// A [SupportTopic] id. Nullable because the website wrote threads before the
  /// picker existed.
  final String? topic;

  final String? lastMessage;

  /// Whether the summary line is NLTC's reply rather than the student's own —
  /// the history list prefixes those with "Support:".
  final bool lastMessageFromAdmin;

  final DateTime? lastActivity;

  /// Replies the student has not opened yet — the badge on the help button.
  final int unreadForStudent;
  final int unreadForAdmin;

  bool get isResolved => status == SupportStatus.resolved;

  static int _int(dynamic v) => v is num ? v.toInt() : 0;

  factory SupportThread.fromMap(String id, Map<String, dynamic> m) {
    final last = m['lastMessage'];
    final ms = tsToMs(m['lastActivity']);
    return SupportThread(
      id: id,
      uid: (m['uid'] ?? id).toString(),
      status: SupportStatus.parse(m['status'] as String?),
      topic: m['topic'] is String && (m['topic'] as String).isNotEmpty
          ? m['topic'] as String
          : null,
      lastMessage: last is Map ? last['text']?.toString() : null,
      lastMessageFromAdmin: last is Map && last['senderRole'] == 'admin',
      lastActivity: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      unreadForStudent: _int(m['unreadForStudent']),
      unreadForAdmin: _int(m['unreadForAdmin']),
    );
  }
}

/// One message in a support thread.
///
/// Support records are create-only on both sides — neither the student nor the
/// admin can edit or delete what was said — so there is nothing mutable here.
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.text,
    required this.fromAdmin,
    this.senderName,
    this.createdAt,
  });

  final String id;
  final String text;

  /// True for the NLTC side of the conversation.
  final bool fromAdmin;

  final String? senderName;

  /// Null for the moment between a local write and the server stamping it.
  final DateTime? createdAt;

  factory SupportMessage.fromMap(String id, Map<String, dynamic> m) {
    final ms = tsToMs(m['createdAt']);
    return SupportMessage(
      id: id,
      text: (m['text'] ?? '').toString(),
      fromAdmin: m['senderRole'] == 'admin',
      senderName: m['senderName']?.toString(),
      createdAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }
}
