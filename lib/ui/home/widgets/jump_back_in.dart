import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/exam_result.dart';
import '../../core/state/dashboard_controller.dart';
import '../../core/state/practice_controller.dart';
import '../../core/theme/app_palette.dart';
import '../../practice/exam_setup_sheet.dart';
import 'desk_card.dart';

/// Resume the last subject practised.
///
/// Port of `JumpBackIn`. The score ring is coloured by band, and the meta line
/// says something about the result rather than only reporting it — a student who
/// scored 38% should be told it's worth another go, not left to work that out.
class JumpBackIn extends StatelessWidget {
  const JumpBackIn({
    super.key,
    required this.results,
    required this.isJunior,
  });

  /// Null while loading.
  final List<ExamResult>? results;
  final bool isJunior;

  DashboardView get _practiceView =>
      isJunior ? DashboardView.bece : DashboardView.cbt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final latest = results?.firstOrNull;

    return DeskCard(
      number: '01',
      title: 'Jump Back In',
      trailing: latest == null
          ? null
          : DeskLink(
              label: 'Full history',
              onTap: () =>
                  context.read<DashboardController>().select(_practiceView),
            ),
      child: results == null
          ? const DeskCardSpinner()
          : latest == null
              ? _EmptyBody(
                  onStart: () =>
                      context.read<DashboardController>().select(_practiceView),
                )
              : _ResultBody(
                  result: latest,
                  onPractiseAgain: () => _practiseAgain(context, latest),
                  onNewSession: () =>
                      context.read<DashboardController>().select(_practiceView),
                  scheme: scheme,
                ),
    );
  }

  /// Straight back into the same subject — the web's `mode=study&autostart=1`.
  Future<void> _practiseAgain(BuildContext context, ExamResult result) async {
    final entry = context.read<PracticeController>().entryFor(result.subject);
    await showExamSetupSheet(context, entry, initialTopic: result.topic);
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ScoreDisc(percent: null),
            const SizedBox(width: Tokens.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No practice yet',
                    style: GoogleFonts.fraunces(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your first session is the hardest — and the most important.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s4),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Start your first test'),
          ),
        ),
      ],
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({
    required this.result,
    required this.onPractiseAgain,
    required this.onNewSession,
    required this.scheme,
  });

  final ExamResult result;
  final VoidCallback onPractiseAgain;
  final VoidCallback onNewSession;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final percent = result.percent;
    final verdict = percent < 50
        ? ' · Worth another go 💪'
        : percent >= 70
            ? ' · Strong work!'
            : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ScoreDisc(percent: percent),
            const SizedBox(width: Tokens.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.subject,
                    style: GoogleFonts.fraunces(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${result.correct}/${result.total} correct · '
                    '${_when(result.submittedAt)}$verdict',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s4),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onPractiseAgain,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Practise again'),
              ),
            ),
            const SizedBox(width: Tokens.s2),
            Expanded(
              child: OutlinedButton(
                onPressed: onNewSession,
                child: const Text('New session'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _when(DateTime? at) {
    if (at == null) return 'recently';
    final days = DateTime.now().difference(at).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    return DateFormat('d MMM').format(at);
  }
}

/// The banded score circle — `.dh-jump-score`.
class _ScoreDisc extends StatelessWidget {
  const _ScoreDisc({required this.percent});

  /// Null renders the em-dash placeholder for "no sittings yet".
  final int? percent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = percent;

    final (border, foreground) = switch (value) {
      null => (scheme.outlineVariant, scheme.onSurfaceVariant),
      _ when value >= 70 => (
          const Color(0xFF6EE7B7),
          const Color(0xFF047857),
        ),
      _ when value < 50 => (
          const Color(0xFFFCA5A5),
          const Color(0xFFB91C1C),
        ),
      _ => (BlueprintPalette.b200, BlueprintPalette.b700),
    };

    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: foreground.withValues(alpha: 0.09),
        border: Border.all(color: border, width: 3),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value == null ? '—' : '$value%',
            style: GoogleFonts.fraunces(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              height: 1,
              color: foreground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value == null ? 'SCORE' : 'LAST',
            style: TextStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: foreground.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
