import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../domain/models/app_notification.dart';
import '../core/format.dart';
import '../core/state/notification_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/empty_state.dart';

/// The notification inbox.
///
/// Reads from the device, refreshes from the backend, and never blocks on the
/// network: a failed refresh shows a strip at the top while the cached list
/// stays exactly where it was.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // The list is already in memory from the bell's badge; this catches
    // anything that arrived since the app last looked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationController>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (controller.unread > 0)
            TextButton(
              onPressed: controller.markAllRead,
              child: const Text('Mark all read'),
            ),
          const SizedBox(width: Tokens.s2),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (controller.isLoading)
              LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: scheme.primary,
              ),
            if (controller.error != null && !controller.isLoading)
              _OfflineStrip(message: controller.error!),
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.refresh,
                child: controller.isEmpty
                    ? ListView(
                        // A scrollable is required for pull-to-refresh to work
                        // on an otherwise empty screen.
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: Tokens.s10),
                          EmptyState(
                            icon: Icons.notifications_none_outlined,
                            title: 'No notifications yet',
                            message:
                                'Announcements, class reminders and results '
                                'will show up here.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          Tokens.s4,
                          Tokens.s4,
                          Tokens.s4,
                          Tokens.s10,
                        ),
                        itemCount: controller.items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: Tokens.s3),
                        itemBuilder: (context, i) => _NotificationTile(
                          notification: controller.items[i],
                          onTap: () => _open(controller.items[i]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(AppNotification notification) {
    context.read<NotificationController>().markRead(notification);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NotificationSheet(notification: notification),
    );
  }
}

class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s4,
        vertical: Tokens.s3,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Text(
              '$message Showing what is saved on this device.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  /// Icon by backend `type`. Unknown types fall back to a plain bell rather
  /// than nothing, so a new server-side category never renders a blank tile.
  static IconData _iconFor(String? category) => switch (category) {
        'chat_message' => Icons.forum_outlined,
        'class_reminder' || 'live_class' => Icons.videocam_outlined,
        'blog_published' => Icons.article_outlined,
        'payment' || 'subscription' => Icons.receipt_long_outlined,
        'welcome' => Icons.celebration_outlined,
        'center_announcement_alert' || 'announcement' => Icons.campaign_outlined,
        _ => Icons.notifications_none_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final unread = !notification.read;

    return Material(
      color: unread ? scheme.primaryContainer.withValues(alpha: 0.35)
                    : scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(Tokens.rLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rLg),
        child: Container(
          padding: const EdgeInsets.all(Tokens.s4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.rLg),
            border: Border.all(
              color: unread ? scheme.primary.withValues(alpha: 0.35)
                            : scheme.outlineVariant,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(Tokens.rSm),
                ),
                child: Icon(
                  _iconFor(notification.category),
                  size: 20,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: text.bodyLarge?.copyWith(
                              fontWeight:
                                  unread ? FontWeight.w800 : FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: Tokens.s2),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: Tokens.s1),
                      Text(
                        notification.body,
                        style: text.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: Tokens.s2),
                    Text(
                      relativeTime(notification.createdAt),
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationSheet extends StatelessWidget {
  const _NotificationSheet({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s5,
          0,
          Tokens.s5,
          Tokens.s6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.title, style: text.headlineSmall),
            const SizedBox(height: Tokens.s2),
            Text(
              DateFormat('d MMM yyyy, h:mm a').format(notification.createdAt),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Tokens.s4),
            Text(notification.body, style: text.bodyLarge),
            const SizedBox(height: Tokens.s6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
