import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/exam_result_repository.dart';
import '../../data/repositories/subject_repository.dart';
import '../../domain/models/question.dart';
import '../../domain/models/subject.dart';
import '../core/anti_cheat.dart';
import '../core/format.dart';
import '../core/state/session_controller.dart';
import '../core/state/xp_service.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/anti_cheat_warning.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/calculator.dart';
import '../core/widgets/question_body.dart';
import '../core/widgets/score_ring.dart';
import '../exam/exam_review_screen.dart';
import '../exam/widgets/option_tile.dart';

/// Which stage of the quiz is on screen.
enum _Phase { setup, loading, exam, results }

/// The NLTC Official Quiz.
///
/// Port of `src/pages/dashboard/NLTCQuizView.jsx`: pick a subject and a length,
/// sit an untimed but invigilated set drawn from the curated bank, then see the
/// score with a full review. Leaving the app three times submits for you.
class OfficialQuizScreen extends StatefulWidget {
  const OfficialQuizScreen({super.key});

  @override
  State<OfficialQuizScreen> createState() => _OfficialQuizScreenState();
}

class _OfficialQuizScreenState extends State<OfficialQuizScreen>
    with WidgetsBindingObserver, AntiCheatObserver {
  static const _countOptions = [10, 20, 30, 40, 50];

  /// The web reads up to 300 questions per subject before shuffling.
  static const _poolSize = 300;

  _Phase _phase = _Phase.setup;

  List<Subject> _subjects = const [];
  Subject? _subject;
  int _count = 20;

  List<Question> _questions = const [];

  /// Question index → chosen option key.
  final Map<int, String> _answers = {};

  int _index = 0;
  Duration _elapsed = Duration.zero;
  Timer? _clock;

  bool _warningOpen = false;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    final subjects = await context
        .read<SubjectRepository>()
        .decorated(SubjectCategory.senior);
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _subject ??= subjects.isEmpty ? null : subjects.first;
    });
  }

  Future<void> _start() async {
    final subject = _subject;
    if (subject == null) return;

    setState(() {
      _phase = _Phase.loading;
      _answers.clear();
      _index = 0;
      _elapsed = Duration.zero;
      _warningOpen = false;
    });

    try {
      // Always a fresh read, as on the web: new questions and corrected answer
      // keys have to show up immediately, so this deliberately skips the cache.
      final snap = await FirebaseFirestore.instance
          .collection('questions')
          .where('subject', isEqualTo: subject.name)
          .limit(_poolSize)
          .get();

      final pool = snap.docs
          .map((d) => Question.fromMap(d.id, d.data()))
          .where((q) => q.isUsable)
          .toList()
        ..shuffle();

      if (!mounted) return;
      if (pool.isEmpty) {
        showToast(
          'No questions found for ${subject.name}. The admin may not have '
          'added any yet.',
          variant: ToastVariant.error,
        );
        setState(() => _phase = _Phase.setup);
        return;
      }

      setState(() {
        _questions = pool.take(_count).toList();
        _phase = _Phase.exam;
      });
      startAntiCheat();
      _startClock();
    } catch (_) {
      if (!mounted) return;
      showToast('Failed to load questions', variant: ToastVariant.error);
      setState(() => _phase = _Phase.setup);
    }
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  int get _correctCount => [
        for (var i = 0; i < _questions.length; i++)
          if (_answers[i] == _questions[i].answerKey) i,
      ].length;

  void _submit() {
    if (_phase != _Phase.exam) return;
    _clock?.cancel();
    stopAntiCheat();

    final correct = _correctCount;
    final total = _questions.length;
    final percent = total == 0 ? 0.0 : correct / total * 100;

    setState(() => _phase = _Phase.results);

    // The history table reads from a cached query, so it has to be dropped or
    // this sitting won't appear until the TTL runs out.
    final uid = context.read<SessionController>().account?.uid;
    if (uid != null) context.read<ExamResultRepository>().invalidate(uid);

    context.read<XpService>().recordSession(
      subject: _subject?.name ?? 'General',
      exam: 'nltc_quiz',
      score: percent,
      correct: correct,
      total: total,
    );
  }

  void _retry() => setState(() {
        _phase = _Phase.setup;
        _questions = const [];
        _answers.clear();
      });

  // ── Anti-cheat ────────────────────────────────────────────────────────────

  @override
  void onAntiCheatViolation(int count) {
    if (mounted) setState(() => _warningOpen = true);
  }

  @override
  void onAntiCheatAutoSubmit() {
    if (!mounted) return;
    setState(() => _warningOpen = true);
    Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      _submit();
      setState(() => _warningOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          switch (_phase) {
            _Phase.setup => _setup(),
            _Phase.loading => const Center(child: CircularProgressIndicator()),
            _Phase.exam => _exam(),
            _Phase.results => _results(),
          },
          if (_warningOpen)
            AntiCheatWarning(
              violations: antiCheatViolations,
              maxViolations: antiCheatMaxViolations,
              isFinal: antiCheatAutoSubmitted,
              onDismiss: () => setState(() => _warningOpen = false),
            ),
        ],
      );

  // ── Setup ─────────────────────────────────────────────────────────────────

  Widget _setup() {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s4, Tokens.s4, Tokens.s10),
      children: [
        AppCard(
          padding: const EdgeInsets.all(Tokens.s5),
          child: Column(
            children: [
              Icon(
                Icons.description_rounded,
                size: 40,
                color: scheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                'NLTC Official Quiz',
                textAlign: TextAlign.center,
                style: GoogleFonts.fraunces(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Test yourself with our curated question bank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Tokens.s6),
              DropdownButtonFormField<Subject>(
                initialValue: _subject,
                decoration: const InputDecoration(labelText: 'Subject'),
                isExpanded: true,
                items: [
                  for (final subject in _subjects)
                    DropdownMenuItem(
                      value: subject,
                      child: Text(subject.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() => _subject = value),
              ),
              const SizedBox(height: Tokens.s4),
              DropdownButtonFormField<int>(
                initialValue: _count,
                decoration: const InputDecoration(
                  labelText: 'Number of questions',
                ),
                items: [
                  for (final n in _countOptions)
                    DropdownMenuItem(value: n, child: Text('$n questions')),
                ],
                onChanged: (value) => setState(() => _count = value ?? _count),
              ),
              const SizedBox(height: Tokens.s5),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _subject == null ? null : _start,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Start Quiz'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Exam ──────────────────────────────────────────────────────────────────

  Widget _exam() {
    final scheme = Theme.of(context).colorScheme;
    final question = _questions[_index];
    final chosen = _answers[_index];

    return SelectionContainer.disabled(
      child: Column(
        children: [
          // Status strip: elapsed clock, progress, calculator, question map.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s4,
              vertical: Tokens.s2,
            ),
            color: scheme.surfaceContainerLow,
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: scheme.primary),
                const SizedBox(width: 5),
                Text(
                  formatDuration(_elapsed.inSeconds),
                  style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Text(
                  '${_answers.length}/${_questions.length} answered',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: Tokens.s2),
                IconButton(
                  onPressed: () => Calculator.show(context),
                  icon: const Icon(Icons.calculate_rounded, size: 20),
                  tooltip: 'Calculator',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: _openQuestionMap,
                  icon: const Icon(Icons.grid_view_rounded, size: 19),
                  tooltip: 'Question map',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Tokens.s4,
                Tokens.s4,
                Tokens.s4,
                Tokens.s4,
              ),
              children: [
                Text(
                  'Question ${_index + 1} of ${_questions.length}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                RichQuestionText(
                  html: question.text,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: Tokens.s4),
                for (final entry in question.options.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Tokens.s2),
                    child: OptionTile(
                      optionKey: entry.key,
                      label: entry.value,
                      selected: chosen == entry.key,
                      onTap: () =>
                          setState(() => _answers[_index] = entry.key),
                    ),
                  ),
              ],
            ),
          ),
          // Nav bar
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.s4,
                Tokens.s2,
                Tokens.s4,
                Tokens.s3,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _index == 0 ? null : () => setState(() => _index--),
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                      label: const Text('Previous'),
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                  Expanded(
                    child: _index == _questions.length - 1
                        ? FilledButton.icon(
                            onPressed: _confirmSubmit,
                            icon: const Icon(Icons.send_rounded, size: 17),
                            label: const Text('Submit'),
                          )
                        : FilledButton.icon(
                            onPressed: () => setState(() => _index++),
                            icon: const Icon(Icons.chevron_right_rounded, size: 18),
                            label: const Text('Next'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSubmit() async {
    final unanswered = _questions.length - _answers.length;
    if (unanswered == 0) {
      _submit();
      return;
    }

    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit quiz?'),
        content: Text(
          '$unanswered question${unanswered == 1 ? '' : 's'} '
          '${unanswered == 1 ? 'is' : 'are'} still unanswered. '
          'They will be marked wrong.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (submit ?? false) _submit();
  }

  /// `QuestionMap` — jump to any question, with answered ones marked.
  void _openQuestionMap() => showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) {
          final scheme = Theme.of(sheetContext).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Tokens.s4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Questions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: Tokens.s3),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < _questions.length; i++)
                            _MapTile(
                              number: i + 1,
                              answered: _answers.containsKey(i),
                              current: i == _index,
                              onTap: () {
                                setState(() => _index = i);
                                Navigator.of(sheetContext).pop();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  // ── Results ───────────────────────────────────────────────────────────────

  Widget _results() {
    final scheme = Theme.of(context).colorScheme;
    final correct = _correctCount;
    final total = _questions.length;
    final percent = total == 0 ? 0.0 : correct / total * 100;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s4, Tokens.s4, Tokens.s10),
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: Tokens.s6),
          child: Column(
            children: [
              ScoreRing(percent: percent, size: 128),
              const SizedBox(height: Tokens.s4),
              Text(
                '$correct of $total correct',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_subject?.name ?? ''} · ${formatDuration(_elapsed.inSeconds)}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s4),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ExamReviewScreen(
                  subject: _subject?.name ?? 'Official Quiz',
                  questions: _questions,
                  answers: {
                    for (var i = 0; i < _questions.length; i++)
                      if (_answers[i] != null) _questions[i].id: _answers[i]!,
                  },
                  examMode: 'quiz',
                ),
              ),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.fact_check_rounded, size: 18),
            label: const Text('Review Answers'),
          ),
        ),
        const SizedBox(height: Tokens.s2),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _retry,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Take Another Quiz'),
          ),
        ),
      ],
    );
  }
}

class _MapTile extends StatelessWidget {
  const _MapTile({
    required this.number,
    required this.answered,
    required this.current,
    required this.onTap,
  });

  final int number;
  final bool answered;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final background = current
        ? scheme.primary
        : answered
            ? scheme.primaryContainer
            : scheme.surfaceContainerHigh;
    final foreground = current
        ? scheme.onPrimary
        : answered
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(Tokens.rSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rSm),
        child: SizedBox(
          width: Tokens.minTouchTarget,
          height: 40,
          child: Center(
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
