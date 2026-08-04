import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state/dashboard_badge_controller.dart';
import '../core/theme/app_palette.dart';
import 'support_sheet.dart';

/// The floating "reach a human" button.
///
/// Mounted by [AppShell] rather than by any one screen, so it rides along on
/// every student view — including the locked one, which is precisely when a
/// student whose payment has not been credited most needs it. That is the whole
/// reason support is not built on the Messages screen: Messages is not a free
/// view, so the account most likely to need help cannot open it.
///
/// It does not need hiding during an exam the way the web's FAB does: sittings
/// are pushed as full-screen routes here, so the shell's button is already
/// behind them and cannot collide with the floating calculator.
class SupportFab extends StatelessWidget {
  const SupportFab({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.select<DashboardBadgeController, int>(
      (c) => c.supportUnread,
    );

    return FloatingActionButton(
      onPressed: () => showSupportSheet(context),
      backgroundColor: BlueprintPalette.b600,
      foregroundColor: BlueprintPalette.white,
      tooltip: 'Help & Support',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.headset_mic_rounded),
          if (unread > 0)
            Positioned(
              top: -6,
              right: -8,
              child: Container(
                constraints: const BoxConstraints(minWidth: 17),
                height: 17,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: BlueprintPalette.b600, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: BlueprintPalette.white,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
