import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/api_client.dart';
import '../../../data/services/push_service.dart';
import '../../../domain/models/app_notification.dart';

/// Backs the inbox and the app-bar bell.
///
/// Reads the device copy first and then refreshes in the background, so the
/// list is never empty while the network makes up its mind. Push messages that
/// land with the app open are folded in immediately.
class NotificationController extends ChangeNotifier {
  NotificationController({
    required NotificationRepository repository,
    required PushService push,
  })  : _repository = repository,
        _push = push;

  final NotificationRepository _repository;
  final PushService _push;

  StreamSubscription<AppNotification>? _pushSub;
  String? _uid;

  List<AppNotification> _items = const [];
  int _unread = 0;
  bool _loading = false;
  String? _error;

  List<AppNotification> get items => _items;
  int get unread => _unread;
  bool get isLoading => _loading;

  /// Why the last refresh failed, if it did. The cached list is still valid.
  String? get error => _error;

  bool get isEmpty => _items.isEmpty && !_loading;

  /// Point the inbox at a student, or at nobody on sign-out.
  ///
  /// Called from the provider graph on every session change, so it must be
  /// cheap and idempotent when the uid hasn't actually moved. The work is
  /// deferred by a microtask because that call happens inside a build — a
  /// synchronous `notifyListeners` here would rebuild mid-frame.
  void bindTo(String? uid) {
    if (uid == _uid) return;
    _uid = uid;
    Future.microtask(() => _applyBinding(uid));
  }

  void _applyBinding(String? uid) {
    // A second session change may have landed while the microtask waited.
    if (uid != _uid) return;

    if (uid == null) {
      _pushSub?.cancel();
      _pushSub = null;
      _items = const [];
      _unread = 0;
      _error = null;
      notifyListeners();
      return;
    }

    _pushSub ??= _push.incoming.listen(_onPush);
    unawaited(_push.start(onToken: _repository.registerDevice));
    unawaited(load());
  }

  /// Device copy first, then the server.
  Future<void> load() async {
    _items = await _repository.cached();
    _unread = await _repository.unreadCount();
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    if (_uid == null || _loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _items = await _repository.refresh();
      _unread = await _repository.unreadCount();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load your notifications.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(AppNotification notification) async {
    if (notification.read) return;
    _replace(notification.copyWith(read: true));
    await _repository.markRead(notification.id);
  }

  Future<void> markAllRead() async {
    if (_unread == 0) return;
    _items = _items.map((n) => n.copyWith(read: true)).toList();
    _unread = 0;
    notifyListeners();
    await _repository.markAllRead();
  }

  Future<void> _onPush(AppNotification notification) async {
    await _repository.record(notification);
    _items = [notification, ..._items.where((n) => n.id != notification.id)];
    _unread++;
    notifyListeners();
  }

  void _replace(AppNotification updated) {
    _items = [
      for (final n in _items) n.id == updated.id ? updated : n,
    ];
    _unread = _items.where((n) => !n.read).length;
    notifyListeners();
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    super.dispose();
  }
}
