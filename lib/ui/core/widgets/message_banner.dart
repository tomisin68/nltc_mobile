import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

enum MessageTone { error, success, info }

/// Inline status message for forms.
///
/// Errors live in the page rather than in a SnackBar so they stay on screen
/// while the student fixes the field, and so screen readers announce them next
/// to the form they belong to.
class MessageBanner extends StatelessWidget {
  const MessageBanner({
    super.key,
    required this.message,
    this.tone = MessageTone.error,
  });

  final String message;
  final MessageTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (background, foreground, icon) = switch (tone) {
      MessageTone.error => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.error_outline,
        ),
      MessageTone.success => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          Icons.check_circle_outline,
        ),
      MessageTone.info => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.info_outline,
        ),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s4,
          vertical: Tokens.s3,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(Tokens.rMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
