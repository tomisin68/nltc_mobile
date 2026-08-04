import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// The "nothing here yet" panel.
///
/// Always says what to do next rather than only that the list is empty — an
/// empty screen with no way forward is the fastest way to lose a student.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Tightens the padding for use inside a card rather than a whole screen.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Tokens.s6,
        vertical: compact ? Tokens.s6 : Tokens.s10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 52 : 68,
            height: compact ? 52 : 68,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: compact ? 24 : 30,
              color: scheme.onPrimaryContainer,
            ),
          ),
          SizedBox(height: compact ? Tokens.s4 : Tokens.s5),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: Tokens.s2),
          Text(
            message,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: Tokens.s5),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
