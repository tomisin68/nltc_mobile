import 'package:flutter/material.dart';

import 'theme/app_palette.dart';

/// Which accent the toast carries on its leading edge.
enum ToastVariant { success, error, info }

/// Lets any layer raise a toast, including repositories and controllers that
/// have no `BuildContext`.
///
/// The web exposes a module-level `showToast` from its ToastContext and calls it
/// from hooks and utils alike; this key is how the same shape works in Flutter.
/// Wired into `MaterialApp.scaffoldMessengerKey`.
final GlobalKey<ScaffoldMessengerState> toastMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Shows a toast. Port of `showToast` in `src/contexts/ToastContext.jsx`.
///
/// Silently does nothing when the app has no messenger mounted — a toast is
/// never important enough to crash a background task over.
void showToast(String message, {ToastVariant variant = ToastVariant.info}) {
  final messenger = toastMessengerKey.currentState;
  if (messenger == null) return;

  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      // 3s, matching the web's dismiss timing.
      duration: const Duration(seconds: 3),
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      content: _ToastBody(message: message, variant: variant),
    ),
  );
}

/// `.toast` — navy slab, accent rule down the leading edge.
class _ToastBody extends StatelessWidget {
  const _ToastBody({required this.message, required this.variant});

  final String message;
  final ToastVariant variant;

  @override
  Widget build(BuildContext context) {
    final (accent, icon) = switch (variant) {
      ToastVariant.success => (
          BlueprintPalette.success,
          Icons.check_circle_rounded,
        ),
      ToastVariant.error => (BlueprintPalette.error, Icons.error_rounded),
      ToastVariant.info => (BlueprintPalette.b300, Icons.info_rounded),
    };

    return Container(
      decoration: BoxDecoration(
        color: BlueprintPalette.b900,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        border: Border(left: BorderSide(color: accent, width: 3)),
        boxShadow: [
          BoxShadow(
            color: BlueprintPalette.ink.withValues(alpha: 0.3),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s4, vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 17, color: accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: BlueprintPalette.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
