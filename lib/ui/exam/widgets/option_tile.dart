import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/question_body.dart';

/// One answer choice.
///
/// Used by the runner (where [correct] is null during a timed sitting) and by
/// the review screen (where it is always known). Correctness is never carried
/// by colour alone — the letter badge changes to a tick or a cross too, so the
/// tile still reads for a colour-blind student.
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.optionKey,
    required this.label,
    required this.selected,
    this.correct,
    this.onTap,
  });

  /// `'a'`–`'d'`.
  final String optionKey;
  final String label;
  final bool selected;

  /// Null while the answer is still hidden; otherwise whether *this* option is
  /// the right one.
  final bool? correct;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final revealed = correct != null;
    final isRightAnswer = correct ?? false;
    final isWrongPick = revealed && selected && !isRightAnswer;

    final (border, background, accent) = switch (true) {
      _ when revealed && isRightAnswer => (
          BlueprintPalette.success,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      _ when isWrongPick => (
          scheme.error,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      _ when selected => (
          scheme.primary,
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      _ => (
          scheme.outlineVariant,
          scheme.surfaceContainerLowest,
          scheme.onSurface,
        ),
    };

    final badgeIcon = switch (true) {
      _ when revealed && isRightAnswer => Icons.check,
      _ when isWrongPick => Icons.close,
      _ => null,
    };

    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.rMd),
          child: AnimatedContainer(
            duration: Motion.fast,
            constraints: const BoxConstraints(minHeight: Tokens.minTouchTarget),
            padding: const EdgeInsets.all(Tokens.s4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.rMd),
              border: Border.all(
                color: border,
                width: selected || (revealed && isRightAnswer) ? 1.8 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selected || (revealed && isRightAnswer)
                        ? border
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(Tokens.rXs),
                  ),
                  alignment: Alignment.center,
                  child: badgeIcon != null
                      ? Icon(badgeIcon, size: 18, color: scheme.onPrimary)
                      : Text(
                          optionKey.toUpperCase(),
                          style: text.labelLarge?.copyWith(
                            color: selected
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: RichQuestionText(
                      // Options carry markup as often as the question does —
                      // an index, a fraction, a chemical formula.
                      html: label,
                      style: text.bodyLarge?.copyWith(color: accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
