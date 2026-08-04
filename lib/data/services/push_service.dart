import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../domain/models/app_notification.dart';

/// Firebase Cloud Messaging plumbing, kept away from the UI.
///
/// Only foreground messages are handled here. When the app is backgrounded or
/// closed, FCM draws the system notification itself from the `notification`
/// payload the backend sends — duplicating that with a local notification would
/// show the student two of everything.
class PushService {
  PushService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
  final _incoming = StreamController<AppNotification>.broadcast();

  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<String>? _tokenSub;

  /// Messages that arrived while the student was looking at the app.
  Stream<AppNotification> get incoming => _incoming.stream;

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

      _messageSub ??= FirebaseMessaging.onMessage.listen((message) {
        _incoming.add(
          AppNotification.fromPush(
            id: message.messageId ??
                'push-${DateTime.now().millisecondsSinceEpoch}',
            title: message.notification?.title,
            body: message.notification?.body,
            data: message.data,
          ),
        );
      });

      // A token can be rotated by the OS at any time; re-register when it is,
      // or pushes quietly stop arriving on that device.
      _tokenSub ??= _messaging.onTokenRefresh.listen(
        (token) => onToken(token, platform).catchError((_) {}),
      );

      final token = await _messaging.getToken();
      if (token != null) await onToken(token, platform);
      return token;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _messageSub?.cancel();
    await _tokenSub?.cancel();
    await _incoming.close();
  }
}
