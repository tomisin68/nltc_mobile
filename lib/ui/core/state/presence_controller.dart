import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/presence_repository.dart';
import '../../../domain/models/user_presence.dart';

/// Who is online — this student, and everyone they are talking to.
///
/// One object owns both halves because they are the same feature seen from two
/// sides. Outwards it keeps this student's own `online` flag honest with a
/// heartbeat and the app lifecycle; inwards it holds one document listener per
/// person the UI is currently showing, shared between the conversation list and
/// whichever conversation is open, so opening a chat with someone already in the
/// list costs nothing.
///
/// Screens register interest under a key and drop it when they go, rather than
/// each keeping their own subscription: the list and the thread almost always
/// want the same person, and two listeners on one document is one too many.
class PresenceController extends ChangeNotifier {
  PresenceController({required PresenceRepository presence})
      : _presence = presence;

  final PresenceRepository _presence;

  String? _myUid;

  /// Screen key → the uids that screen is showing.
  final Map<String, Set<String>> _interests = {};

  final Map<String, StreamSubscription<UserPresence>> _subscriptions = {};
  final Map<String, UserPresence> _known = {};

  Timer? _heartbeat;
  Timer? _ticker;
  bool _foreground = true;
  bool _disposed = false;

  /// Refreshed well inside [UserPresence.staleAfter] so the window never closes
  /// on a student who is sitting right there reading.
  ///
  /// A third of the staleness window, not half: one beat lost to a moment of no
  /// signal must not be enough to make this student flicker offline on somebody
  /// else's screen.
  static const _heartbeatInterval = Duration(seconds: 60);

  /// `isOnline` is partly a function of the clock, so a screen showing someone
  /// who went quiet has to be told to re-read it even though nothing was written.
  static const _tick = Duration(seconds: 30);

  // ─── This student ──────────────────────────────────────────────────────────

  /// Follows the signed-in account. Signing out marks the old account away.
  void bindTo(String? uid) {
    if (_myUid == uid) return;

    final previous = _myUid;
    _myUid = uid;
    if (previous != null) unawaited(_presence.setOffline(previous));

    _heartbeat?.cancel();
    _heartbeat = null;
    if (uid == null) return;

    if (_foreground) _beginHeartbeat(uid);
  }

  void _beginHeartbeat(String uid) {
    unawaited(_presence.setOnline(uid));
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
      _heartbeatInterval,
      (_) => unawaited(_presence.setOnline(uid)),
    );
  }

  /// Called from the shell's lifecycle callback.
  ///
  /// A backgrounded app is not "online": the student cannot read what arrives,
  /// and a green dot on someone who has locked their phone is worse than no dot.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;

    final uid = _myUid;
    if (uid == null) return;

    if (foreground) {
      _beginHeartbeat(uid);
    } else {
      _heartbeat?.cancel();
      _heartbeat = null;
      unawaited(_presence.setOffline(uid));
    }
  }

  // ─── Everyone else ─────────────────────────────────────────────────────────

  UserPresence presenceOf(String? uid) =>
      uid == null ? UserPresence.unknown : _known[uid] ?? UserPresence.unknown;

  bool isOnline(String? uid) => presenceOf(uid).isOnline;

  /// Declares which people [key] is currently showing.
  ///
  /// Safe to call on every build: identical sets are ignored, so a rebuild
  /// triggered by a presence change cannot loop.
  void track(String key, Iterable<String> uids) {
    final wanted = uids.where((u) => u != _myUid).toSet();
    final existing = _interests[key];
    if (existing != null && _sameSet(existing, wanted)) return;

    if (wanted.isEmpty) {
      _interests.remove(key);
    } else {
      _interests[key] = wanted;
    }
    _reconcile();
  }

  void untrack(String key) {
    if (_interests.remove(key) == null) return;
    _reconcile();
  }

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  void _reconcile() {
    final wanted = {for (final set in _interests.values) ...set};

    for (final uid in _subscriptions.keys.toList()) {
      if (wanted.contains(uid)) continue;
      _subscriptions.remove(uid)?.cancel();
      _known.remove(uid);
    }

    for (final uid in wanted) {
      if (_subscriptions.containsKey(uid)) continue;
      _subscriptions[uid] = _presence.watch(uid).listen(
        (presence) => _remember(uid, presence),
        onError: (_) {/* a profile we may not read; leave them unknown */},
      );
    }

    if (wanted.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    } else {
      _ticker ??= Timer.periodic(_tick, (_) => _notify());
    }
  }

  void _remember(String uid, UserPresence presence) {
    final before = _known[uid];
    _known[uid] = presence;
    // Only when something a screen could draw actually moved — the raw document
    // changes on every XP award, and none of that belongs in a rebuild here.
    if (before == null ||
        before.isOnline != presence.isOnline ||
        before.name != presence.name ||
        before.photo != presence.photo ||
        before.lastSeen != presence.lastSeen) {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    _ticker?.cancel();
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
    final uid = _myUid;
    if (uid != null) unawaited(_presence.setOffline(uid));
    super.dispose();
  }
}
