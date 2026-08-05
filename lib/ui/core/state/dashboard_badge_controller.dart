import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../data/repositories/chat_repository.dart';
import '../../../domain/models/app_user.dart' show tsToMs;

/// The two counters the sidebar decorates its nav with: is a class live right
/// now, and how many chat messages are waiting.
///
/// Mirrors the effects in the web app's `src/components/layout/Sidebar.jsx`,
/// including the choice of mechanism for each — the live check is a cheap
/// two-minute poll (the web caches it under `TTL.LIVE_SESSIONS`), while chat
/// unread is a real-time listener because a message arriving needs to show up
/// immediately.
///
/// That listener is also where delivery receipts are written from. It is the one
/// subscription to this student's conversations that outlives every screen, so
/// it is the only place that can honestly answer "did it reach them?" while they
/// are somewhere else entirely in the app.
class DashboardBadgeController extends ChangeNotifier {
  DashboardBadgeController({
    required ChatRepository chats,
    FirebaseFirestore? firestore,
  })  : _chats = chats,
        _db = firestore ?? FirebaseFirestore.instance;

  final ChatRepository _chats;
  final FirebaseFirestore _db;

  /// Matches `TTL.LIVE_SESSIONS` in `src/utils/firestoreCache.js`.
  static const _livePollInterval = Duration(minutes: 2);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _supportSub;
  Timer? _liveTimer;
  String? _uid;

  bool _liveActive = false;
  int _chatUnread = 0;
  int _supportUnread = 0;

  /// True while at least one session has `status == 'live'`.
  bool get liveActive => _liveActive;

  int get chatUnread => _chatUnread;

  /// Unanswered replies from the NLTC support desk — the badge on the floating
  /// help button and on the sidebar's Help & Support link.
  int get supportUnread => _supportUnread;

  /// Points the controller at a student, or clears it when [uid] is null.
  ///
  /// Safe to call on every rebuild — a repeat call with the same uid is ignored,
  /// so this can hang off a proxy provider without restarting the listeners.
  void bindTo(String? uid) {
    if (uid == _uid) return;
    _uid = uid;
    _teardown();

    if (uid == null) {
      _liveActive = false;
      _chatUnread = 0;
      _supportUnread = 0;
      notifyListeners();
      return;
    }

    _watchChats(uid);
    _watchSupport(uid);
    _pollLive();
    _liveTimer = Timer.periodic(_livePollInterval, (_) => _pollLive());
  }

  /// Unread replies summed across every conversation this student has open.
  ///
  /// Watched for the whole session rather than from the help button itself,
  /// because that button is also drawn on the locked screen and a student
  /// waiting on an answer about their payment should see the reply land
  /// without opening anything. Queried on the `uid` field, not the document
  /// id: a solved request stays solved and the next one is a new document.
  void _watchSupport(String uid) {
    _supportSub = _db
        .collection('supportThreads')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .listen(
      (snap) {
        var total = 0;
        for (final doc in snap.docs) {
          final raw = doc.data()['unreadForStudent'];
          if (raw is num) total += raw.toInt();
        }
        if (total == _supportUnread) return;
        _supportUnread = total;
        notifyListeners();
      },
      // A student who has never asked for help matches nothing, and the rules
      // reject the read outright before they do — neither is worth surfacing.
      onError: (_) {},
    );
  }

  void _watchChats(String uid) {
    _chatSub = _db
        .collection('chats')
        .where('members', arrayContains: uid)
        .snapshots()
        .listen(
      (snap) {
        var total = 0;
        for (final doc in snap.docs) {
          final data = doc.data();
          final counts = data['unreadCount'];
          if (counts is Map && counts[uid] is num) {
            total += (counts[uid] as num).toInt();
          }
          _acknowledge(doc.id, data, uid);
        }
        if (total == _chatUnread) return;
        _chatUnread = total;
        notifyListeners();
      },
      // A rules rejection or lost signal leaves the last known count standing —
      // a badge that clears itself would read as "your messages were read".
      onError: (_) {},
    );
  }

  /// chatId → the `lastActivity` a receipt has already been written for.
  ///
  /// Without it this loops: the receipt is a server timestamp, which reads back
  /// as null on the writer's own device until the server confirms it, so the very
  /// snapshot caused by writing one looks exactly like a conversation still
  /// waiting for it.
  final Map<String, int> _acknowledged = {};

  /// Tells the sender their message arrived, if it has and they don't know yet.
  void _acknowledge(String chatId, Map<String, dynamic> data, String uid) {
    final activity = tsToMs(data['lastActivity']);
    if (activity == null) return;

    // Nothing to acknowledge in an empty conversation, and nobody to tell about
    // this student's own messages.
    final last = data['lastMessage'];
    if (last is! Map || last['senderId'] == uid) return;

    final delivered = data['deliveredTo'];
    final mine = delivered is Map ? tsToMs(delivered[uid]) : null;
    if (mine != null && mine >= activity) return;

    if (_acknowledged[chatId] == activity) return;
    _acknowledged[chatId] = activity;
    unawaited(_chats.markDelivered(chatId, uid));
  }

  Future<void> _pollLive() async {
    try {
      final snap = await _db
          .collection('liveSessions')
          .where('status', isEqualTo: 'live')
          .limit(1)
          .get();
      final active = snap.docs.isNotEmpty;
      if (active == _liveActive) return;
      _liveActive = active;
      notifyListeners();
    } catch (_) {
      // Leave the dot as it was rather than claiming the class ended.
    }
  }

  void _teardown() {
    _chatSub?.cancel();
    _chatSub = null;
    _supportSub?.cancel();
    _supportSub = null;
    _acknowledged.clear();
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
