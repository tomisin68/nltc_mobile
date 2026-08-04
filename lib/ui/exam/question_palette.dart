import 'package:flutter/material.dart';

import '../core/state/exam_controller.dart';
import '../core/theme/app_palette.dart';

/// The question grid, opened from the exam toolbar.
///
/// Pops the index the student tapped, so the runner owns navigation and the
/// sheet stays a pure picker.
class QuestionPalette extends StatelessWidget {
  const QuestionPalette({super.key, required this.controller});

  final ExamController controller;

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
            Text('Jump to a question', style: text.titleLarge),
            const SizedBox(height: Tokens.s3),
            Wrap(
              spacing: Tokens.s4,
              runSpacing: Tokens.s2,
              children: [
                _LegendDot(
                  color: scheme.primary,
                  label: '${controller.answeredCount} answered',
                ),
                _LegendDot(
                  color: BlueprintPalette.warning,
                  label: '${controller.flaggedCount} flagged',
                ),
                _LegendDot(
                  color: scheme.outline,
                  label: '${controller.unansweredCount} left',
                ),
              ],
            ),
            const SizedBox(height: Tokens.s5),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // One block per subject, exactly as the web's question map
                    // does it. A single-subject paper has one section, so the
                    // heading is skipped and the grid looks unchanged.
                    for (final section in controller.sections) ...[
                      if (controller.config.isMultiSubject) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: Tokens.s2),
                          child: Text(
                            '${section.name.toUpperCase()}  ·  '
                            '${controller.answeredIn(section)}/${section.length}',
                            style: text.labelSmall?.copyWith(
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: Tokens.s5),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 56,
                          mainAxisSpacing: Tokens.s2,
                          crossAxisSpacing: Tokens.s2,
                          childAspectRatio: 1,
                        ),
                        itemCount: section.length,
                        itemBuilder: (context, i) {
                          final index = section.start + i;
                          return _PaletteCell(
                            // Numbering restarts per subject, the way it does on
                            // a real paper.
                            number: i + 1,
                            status: controller.statusAt(index),
                            isCurrent: index == controller.index,
                            onTap: () => Navigator.of(context).pop(index),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Tokens.s2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      );
}

class _PaletteCell extends StatelessWidget {
  const _PaletteCell({
    required this.number,
    required this.status,
    required this.isCurrent,
    required this.onTap,
  });

  final int number;
  final QuestionStatus status;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (background, foreground) = switch (status) {
      QuestionStatus.answered => (scheme.primary, scheme.onPrimary),
      QuestionStatus.flagged => (
          BlueprintPalette.warning,
          const Color(0xFF3B2503),
        ),
      QuestionStatus.unanswered => (
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
        ),
    };

    return Semantics(
      button: true,
      label: 'Question $number, ${status.name}',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(Tokens.rSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.rSm),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.rSm),
              border: isCurrent
                  ? Border.all(color: scheme.onSurface, width: 2)
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
