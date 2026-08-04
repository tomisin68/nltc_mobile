import 'app_user.dart' show tsToMs;

/// Whether someone is at their phone or their desk right now.
///
/// The website's `usePresence` hook writes `online: true` on `users/{uid}` while
/// its tab is visible and clears it on `beforeunload`, stamping `lastSeen` each
/// time. Neither of those survives a browser being force-quit, a phone running
/// out of battery, or a train going into a tunnel — so the flag on its own is
/// only ever a claim somebody's last living moment made about the future.
///
/// [isOnline] therefore needs both halves to agree: the flag says they meant to
/// be here, and a fresh `lastSeen` says they still are. The app refreshes its own
/// stamp on a heartbeat, which is what keeps the second half true for as long as
/// the student really is reading.
class UserPresence {
  const UserPresence({
    this.online = false,
    this.lastSeen,
    this.name,
    this.photo,
  });

  /// What everyone starts as, and what a uid with no document reads back as.
  static const unknown = UserPresence();

  /// The flag the other client last wrote.
  final bool online;

  final DateTime? lastSeen;

  /// Kept alongside the flags because the same document carries them, and the
  /// conversation list would otherwise show a name the student changed an hour
  /// ago on the website.
  final String? name;
  final String? photo;

  /// How stale `lastSeen` may be before someone counts as away.
  ///
  /// The same three minutes the website allows, and comfortably more than the
  /// app's own heartbeat interval, so a student sitting still reading never
  /// blinks out between beats.
  static const staleAfter = Duration(minutes: 3);

  /// True only while both the flag and the stamp still say so.
  ///
  /// A cleared flag is believed immediately — someone who has just backgrounded
  /// the app is gone, whatever their stamp says — and a set flag expires with
  /// the stamp, which is what stops a killed app or a dead battery leaving
  /// somebody permanently green.
  bool get isOnline {
    if (!online) return false;
    final seen = lastSeen;
    if (seen == null) return false;
    final since = DateTime.now().difference(seen);
    // A negative age means the other device's clock — or ours — is ahead. That
    // is not evidence of absence, so it counts as present rather than away.
    return since < staleAfter;
  }

  factory UserPresence.fromMap(Map<String, dynamic> m) {
    final first = (m['firstName'] ?? '').toString().trim();
    final last = (m['lastName'] ?? '').toString().trim();
    final full = [first, last].where((p) => p.isNotEmpty).join(' ');
    final seen = tsToMs(m['lastSeen']);

    return UserPresence(
      online: m['online'] == true,
      lastSeen: seen == null ? null : DateTime.fromMillisecondsSinceEpoch(seen),
      name: full.isNotEmpty ? full : (m['displayName']?.toString().trim()),
      photo: (m['profileImage'] ?? m['photoURL'])?.toString(),
    );
  }
}
