import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../notifications/notifications_screen.dart';
import '../state/notification_controller.dart';

/// App-bar bell with an unread count.
///
/// Counts above nine collapse to `9+` so the badge never grows wide enough to
/// crop against the icon.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread =
        context.select<NotificationController, int>((c) => c.unread);
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : '$unread unread notifications',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
      ),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(unread == 0
              ? Icons.notifications_none_outlined
              : Icons.notifications_active_outlined),
          if (unread > 0)
            Positioned(
              right: -5,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: scheme.error,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.surface, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  style: TextStyle(
                    color: scheme.onError,
                    fontSize: 10,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
