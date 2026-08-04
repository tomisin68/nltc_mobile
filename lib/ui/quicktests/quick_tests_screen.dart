import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../data/services/firestore_cache.dart';
import '../../domain/models/quick_test.dart';
import '../core/anti_cheat.dart';
import '../core/state/session_controller.dart';
import '../core/state/xp_service.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/anti_cheat_warning.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/skeleton.dart';

/// Quick Tests — short published sets, answered inline.
///
/// Port of `src/pages/dashboard/QuickTestsView.jsx`. One screen with two phases:
/// the list, and the test itself. Answers are revealed with their explanations on
/// submit, and leaving the app three times submits for you.
class QuickTestsScreen extends StatefulWidget {
  const QuickTestsScreen({super.key});

  @override
  State<QuickTestsScreen> createState() => _QuickTestsScreenState();
}

class _QuickTestsScreenState extends State<QuickTestsScreen>
    with WidgetsBindingObserver, AntiCheatObserver {
  QuickTest? _active;

  /// Question index → chosen letter.
  final Map<int, String> _answers = {};

  bool _submitted = false;
  ({int correct, int total, int percent})? _score;

  bool _warningOpen = false;

  void _start(QuickTest test) {
    setState(() {
      _active = test;
      _answers.clear();
      _submitted = false;
      _score = null;
      _warningOpen = false;
    });
    startAntiCheat();
  }

  void _exit() {
    stopAntiCheat();
    setState(() {
      _active = null;
      _warningOpen = false;
    });
  }

  void _answer(int index, String letter) {
    if (_submitted) return;
    setState(() => _answers[index] = letter);
  }

  void _submit() {
    final test = _active;
    if (test == null || _submitted) return;

    final questions = test.questions;
    final correct = [
      for (var i = 0; i < questions.length; i++)
        if (questions[i].isCorrect(_answers[i])) i,
    ].length;
    final total = questions.length;
    final percent = total == 0 ? 0 : (correct / total * 100).round();

    stopAntiCheat();
    setState(() {
      _score = (correct: correct, total: total, percent: percent);
      _submitted = true;
    });

    // The exam history table reads from a cached query, so it has to be dropped
    // or this sitting won't appear until the TTL runs out.
    final uid = context.read<SessionController>().account?.uid;
    if (uid != null) {
      context.read<FirestoreCache>().invalidate('userResults_$uid');
    }

    context.read<XpService>().recordSession(
      subject: test.subject ?? 'General',
      exam: 'quick_test',
      score: percent,
      correct: correct,
      total: total,
    );
  }

  // ── Anti-cheat ────────────────────────────────────────────────────────────

  @override
  void onAntiCheatViolation(int count) {
    if (!mounted) return;
    setState(() => _warningOpen = true);
  }

  @override
  void onAntiCheatAutoSubmit() {
    if (!mounted) return;
    setState(() => _warningOpen = true);
    // The final panel stays up long enough to be read, then the test submits
    // itself and the results appear behind it.
    Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      _submit();
      setState(() => _warningOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _active == null ? _list() : _runner(_active!);

  // ── The list ──────────────────────────────────────────────────────────────

  Widget _list() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('quickTests')
            .where('status', isEqualTo: 'published')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          final loading = !snapshot.hasData && !snapshot.hasError;
          final tests = (snapshot.data?.docs ?? const [])
              .map((d) => QuickTest.fromJson(d.id, d.data()))
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              0,
              Tokens.s4,
              Tokens.s10,
            ),
            children: [
              const PageHeader(
                title: 'Quick Tests',
                subtitle: 'Short, focused tests to sharpen specific skills.',
              ),
              if (loading)
                AppCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < 4; i++) const SkeletonListItem(),
                    ],
                  ),
                )
              else if (tests.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: Tokens.s6),
                  child: EmptyState(
                    icon: Icons.bolt_outlined,
                    title: 'No quick tests yet',
                    message: 'New tests are added regularly. Check back soon!',
                  ),
                )
              else
                for (final test in tests)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TestRow(test: test, onStart: () => _start(test)),
                  ),
            ],
          );
        },
      );

  // ── The test ──────────────────────────────────────────────────────────────

  Widget _runner(QuickTest test) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // Selection is off while a test is live — the closest phone equivalent of
        // the web blocking copy.
        SelectionContainer.disabled(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              0,
              Tokens.s4,
              Tokens.s10,
            ),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _exit,
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Back to tests',
                  ),
                  Expanded(
                    child: Text(
                      test.title,
                      style: GoogleFonts.fraunces(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.s4),
              for (var i = 0; i < test.questions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.s3),
                  child: _QuestionCard(
                    index: i,
                    question: test.questions[i],
                    chosen: _answers[i],
                    submitted: _submitted,
                    onAnswer: (letter) => _answer(i, letter),
                  ),
                ),
              if (!_submitted)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Submit Test'),
                  ),
                )
              else ...[
                _ScoreCard(score: _score!),
                const SizedBox(height: Tokens.s3),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _exit,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Back to Tests'),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_warningOpen)
          AntiCheatWarning(
            violations: antiCheatViolations,
            maxViolations: antiCheatMaxViolations,
            isFinal: antiCheatAutoSubmitted,
            onDismiss: () => setState(() => _warningOpen = false),
          ),
      ],
    );
  }
}

class _TestRow extends StatelessWidget {
  const _TestRow({required this.test, required this.onStart});

  final QuickTest test;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, size: 24, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  test.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    test.subject,
                    '${test.questions.length} questions',
                    if (test.durationMinutes != null)
                      '${test.durationMinutes} min',
                  ].where((s) => s != null && s.isNotEmpty).join(' · '),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Tokens.s2),
          FilledButton.icon(
            onPressed: test.questions.isEmpty ? null : onStart,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('Start'),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.question,
    required this.chosen,
    required this.submitted,
    required this.onAnswer,
  });

  final int index;
  final InlineQuestion question;
  final String? chosen;
  final bool submitted;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Q${index + 1}. ${question.question}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.5,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in question.options.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _OptionTile(
                letter: entry.key,
                text: entry.value,
                selected: chosen == entry.key,
                isAnswer: question.answer == entry.key,
                submitted: submitted,
                onTap: () => onAnswer(entry.key),
              ),
            ),
          if (submitted && question.explanation != null) ...[
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.all(Tokens.s3),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Tokens.rSm),
                border: Border(
                  left: BorderSide(color: scheme.primary, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb_rounded,
                        size: 13,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Explanation',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    question.explanation!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.quick-option` — with `.opt-correct` / `.opt-wrong` after submission.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.letter,
    required this.text,
    required this.selected,
    required this.isAnswer,
    required this.submitted,
    required this.onTap,
  });

  final String letter;
  final String text;
  final bool selected;
  final bool isAnswer;
  final bool submitted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // After submission the correct answer is always marked, and a wrong choice is
    // marked alongside it — so the student sees both what they picked and what
    // they should have.
    final wasWrong = submitted && selected && !isAnswer;
    final showCorrect = submitted && isAnswer;

    final (background, border, foreground) = showCorrect
        ? (
            scheme.tertiaryContainer,
            scheme.tertiary,
            scheme.onTertiaryContainer,
          )
        : wasWrong
            ? (scheme.errorContainer, scheme.error, scheme.onErrorContainer)
            : selected
                ? (
                    scheme.primaryContainer,
                    scheme.primary,
                    scheme.onPrimaryContainer,
                  )
                : (
                    scheme.surfaceContainerLowest,
                    scheme.outlineVariant,
                    scheme.onSurface,
                  );

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(Tokens.rSm),
      child: InkWell(
        onTap: submitted ? null : onTap,
        borderRadius: BorderRadius.circular(Tokens.rSm),
        child: Container(
          constraints: const BoxConstraints(minHeight: Tokens.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s3,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.rSm),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: foreground.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: Text(
                  letter.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: foreground,
                  ),
                ),
              ),
              if (showCorrect)
                Icon(Icons.check_rounded, size: 17, color: scheme.tertiary)
              else if (wasWrong)
                Icon(Icons.close_rounded, size: 17, color: scheme.error),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.score});

  final ({int correct, int total, int percent}) score;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final passed = score.percent >= 50;
    final accent = passed ? scheme.tertiary : scheme.error;

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s5),
      child: Column(
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 42,
            color: accent,
          ),
          const SizedBox(height: Tokens.s2),
          Text(
            '${score.percent}%',
            style: GoogleFonts.fraunces(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${score.correct} / ${score.total} correct',
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Text(
            passed
                ? 'Great job! Keep it up.'
                : 'Keep practicing — you can do it!',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
