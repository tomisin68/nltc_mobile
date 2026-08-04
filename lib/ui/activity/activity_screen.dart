import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/exam_attempt.dart';
import '../core/state/activity_controller.dart';
import '../core/state/dashboard_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/notification_bell.dart';
import '../core/widgets/score_ring.dart';
import '../core/widgets/section_header.dart';
import 'attempt_tile.dart';

/// Everything the student has actually done: past sittings and their averages.
///
/// Reads only from the device — history is written before it is synced, so this
/// screen is complete with no signal.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ActivityController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: const [NotificationBell(), SizedBox(width: 4)],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.syncNow,
          child: switch (controller) {
            _ when controller.isLoading =>
              const Center(child: CircularProgressIndicator()),
            _ when controller.isEmpty => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: Tokens.s8),
                  EmptyState(
                    icon: Icons.insights_outlined,
                    title: 'No sittings yet',
                    message:
                        'Take your first CBT and your scores, weak topics and '
                        'progress will build up here.',
                    actionLabel: 'Start practising',
                    onAction: () => context
                        .read<DashboardController>()
                        .select(DashboardView.cbt),
                  ),
                ],
              ),
            _ => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  Tokens.s5,
                  Tokens.s4,
                  Tokens.s5,
                  Tokens.s10,
                ),
                children: [
                  _Summary(attempts: controller.items),
                  if (controller.pendingCount > 0) ...[
                    const SizedBox(height: Tokens.s4),
                    _PendingStrip(
                      count: controller.pendingCount,
                      syncing: controller.isSyncing,
                      onSync: controller.syncNow,
                    ),
                  ],
                  const SizedBox(height: Tokens.s6),
                  SectionHeader(
                    title: 'Past sittings',
                    subtitle:
                        '${controller.items.length} saved on this device',
                  ),
                  for (final attempt in controller.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Tokens.s3),
                      child: AttemptTile(attempt: attempt),
                    ),
                ],
              ),
          },
        ),
      ),
    );
  }
}

/// Headline numbers across every saved sitting.
class _Summary extends StatelessWidget {
  const _Summary({required this.attempts});

  final List<ExamAttempt> attempts;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final average =
        attempts.map((a) => a.score).reduce((a, b) => a + b) / attempts.length;
    final questions = attempts.fold<int>(0, (sum, a) => sum + a.total);
    final correct = attempts.fold<int>(0, (sum, a) => sum + a.correct);

    // The subject with the most sittings — where the student is putting the
    // hours in, which is more useful than their single best score.
    final bySubject = <String, int>{};
    for (final a in attempts) {
      if (a.subject.isEmpty) continue;
      bySubject[a.subject] = (bySubject[a.subject] ?? 0) + 1;
    }
    final favourite = bySubject.entries.isEmpty
        ? null
        : bySubject.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s5),
        child: Row(
          children: [
            ScoreRing(
              percent: average,
              size: 96,
              strokeWidth: 9,
              caption: 'average',
            ),
            const SizedBox(width: Tokens.s5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${attempts.length} sitting'
                    '${attempts.length == 1 ? '' : 's'}',
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: Tokens.s2),
                  Text(
                    '$correct of $questions questions correct',
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (favourite != null) ...[
                    const SizedBox(height: Tokens.s1),
                    Text(
                      'Most practised: $favourite',
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingStrip extends StatelessWidget {
  const _PendingStrip({
    required this.count,
    required this.syncing,
    required this.onSync,
  });

  final int count;
  final bool syncing;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        Tokens.s4,
        Tokens.s2,
        Tokens.s2,
        Tokens.s2,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Tokens.rMd),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Text(
              '$count sitting${count == 1 ? '' : 's'} waiting to sync',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: syncing ? null : onSync,
            child: Text(syncing ? 'Syncing…' : 'Sync now'),
          ),
        ],
      ),
    );
  }
}
