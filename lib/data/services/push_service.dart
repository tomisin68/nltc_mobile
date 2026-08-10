import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../domain/models/app_notification.dart';

/// Firebase Cloud Messaging plumbing, kept away from the UI.
///
/// Foreground messages and taps are handled here. When the app is backgrounded
/// or closed, FCM draws the system notification itself from the `notification`
/// payload the backend sends — duplicating that with a local notification would
/// show the student two of everything.
class PushService {
  PushService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
  final _incoming = StreamController<AppNotification>.broadcast();
  final _taps = StreamController<AppNotification>.broadcast();

  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<RemoteMessage>? _tapSub;
  StreamSubscription<String>? _tokenSub;

  AppNotification? _pendingTap;

  /// Messages that arrived while the student was looking at the app.
  Stream<AppNotification> get incoming => _incoming.stream;

  /// Notifications the student tapped in the system tray.
  ///
  /// A tap that launched the app from cold has usually already happened by the
  /// time anything is listening, so the last one is also held in [pendingTap]
  /// for whoever mounts next. Consumers see it on both paths and must ignore an
  /// id they have already acted on.
  Stream<AppNotification> get taps => _taps.stream;

  /// The most recent tap, kept for a listener that wasn't there yet.
  AppNotification? get pendingTap => _pendingTap;

  String get platform => Platform.isIOS ? 'ios' : 'android';

  /// Asks for permission and returns the device token, or null if the student
  /// declined or the platform couldn't mint one. Never throws: push is a
  /// nice-to-have, and a failure here must not block sign-in.
  Future<String?> start({
    required Future<void> Function(String token, String platform) onToken,
  }) async {
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return null;
      }

      _messageSub ??= FirebaseMessaging.onMessage.listen(
        (message) => _incoming.add(_read(message)),
      );

      // Tapped while the app was alive in the background.
      _tapSub ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _emitTap(_read(message)),
      );

      // A token can be rotated by the OS at any time; re-register when it is,
      // or pushes quietly stop arriving on that device.
      _tokenSub ??= _messaging.onTokenRefresh.listen(
        (token) => onToken(token, platform).catchError((_) {}),
      );

      // Tapped while the app was closed: this is what launched it, and it is
      // only ever delivered once, so it has to be asked for rather than
      // listened for.
      final launchedBy = await _messaging.getInitialMessage();
      if (launchedBy != null) _emitTap(_read(launchedBy));

      final token = await _messaging.getToken();
      if (token != null) await onToken(token, platform);
      return token;
    } catch (_) {
      return null;
    }
  }

  AppNotification _read(RemoteMessage message) => AppNotification.fromPush(
        id: message.messageId ?? 'push-${DateTime.now().millisecondsSinceEpoch}',
        title: message.notification?.title,
        body: message.notification?.body,
        data: message.data,
      );

  void _emitTap(AppNotification notification) {
    _pendingTap = notification;
    _taps.add(notification);
  }

  /// Called by whoever acted on a tap, so it isn't acted on twice.
  void clearPendingTap(String id) {
    if (_pendingTap?.id == id) _pendingTap = null;
  }

  Future<void> dispose() async {
    await _messageSub?.cancel();
    await _tapSub?.cancel();
    await _tokenSub?.cancel();
    await _incoming.close();
    await _taps.close();
  }
}
