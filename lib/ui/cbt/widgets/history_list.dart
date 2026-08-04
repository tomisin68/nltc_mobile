import 'package:flutter/material.dart';

import '../../../domain/models/exam_result.dart';
import '../../core/format.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_card.dart';

/// Exam history.
///
/// The web renders `.data-table` with Subject / Type / Score / Date columns. On a
/// phone those four columns become one row per sitting with the score bar beneath
/// it — same information, no horizontal scrolling.
class HistoryList extends StatelessWidget {
  const HistoryList({
    super.key,
    required this.results,
    this.showType = true,
  });

  final List<ExamResult> results;

  /// BECE's history is all one exam type, so the badge would say the same thing
  /// on every row.
  final bool showType;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (var i = 0; i < results.length; i++) ...[
          if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
          _HistoryRow(result: results[i], showType: showType),
        ],
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.result, required this.showType});

  final ExamResult result;
  final bool showType;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final passed = result.percent >= 50;
    final accent = passed ? scheme.tertiary : scheme.error;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s4,
        vertical: Tokens.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (result.topic != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        result.topic!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showType) ...[
                const SizedBox(width: Tokens.s2),
                AppBadge(
                  label: result.examLabel,
                  tone: switch (result.exam) {
                    'nltc_quiz' => BadgeTone.gold,
                    'quick_test' || 'mock' || 'topic' || 'custom' =>
                      BadgeTone.teal,
                    _ => BadgeTone.navy,
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  '${result.percent}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: scheme.surfaceContainerHigh,
                          ),
                        ),
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (result.percent / 100).clamp(0.0, 1.0),
                            child: ColoredBox(color: accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Tokens.s2),
              Text(
                '${result.correct}/${result.total}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Tokens.s3),
              Text(
                formatDate(result.submittedAt),
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
