import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/learning_profile_repository.dart';
import '../../data/repositories/question_repository.dart';
import '../../data/services/local_database.dart';
import '../../domain/models/access_state.dart';
import '../../domain/models/exam_config.dart';
import '../../domain/models/question.dart';
import '../core/state/practice_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/message_banner.dart';
import '../exam/exam_screen.dart';

/// The sheet between "I want to practise Chemistry" and the first question.
///
/// Draws the questions here rather than inside the runner, so a subject with an
/// empty bank fails on this sheet — where there's something to go back to —
/// instead of on a blank exam screen.
///
/// [initialTopic] pre-selects a topic, for the "Take a Test on This Topic" button
/// at the end of a study note — the web's `/cbt?mode=topic&topics=…`.
///
/// [initialMode] preselects timed-exam or study behaviour, for the CBT Practice
/// mode grid and its study-by-subject tiles.
Future<void> showExamSetupSheet(
  BuildContext context,
  SubjectEntry subject, {
  String? initialTopic,
  ExamMode? initialMode,
  String? subjectKey,
  CbtExam? exam,
  bool topicMode = false,
  String bank = QuestionRepository.seniorBank,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ExamSetupSheet(
      subject: subject,
      initialTopic: initialTopic,
      initialMode: initialMode,
      subjectKey: subjectKey,
      exam: exam,
      topicMode: topicMode,
      bank: bank,
    ),
  );
}

class ExamSetupSheet extends StatefulWidget {
  const ExamSetupSheet({
    super.key,
    required this.subject,
    this.initialTopic,
    this.initialMode,
    this.subjectKey,
    this.exam,
    this.topicMode = false,
    this.bank = QuestionRepository.seniorBank,
  });

  final SubjectEntry subject;

  /// A topic to start on, when the student arrived from that topic's notes.
  final String? initialTopic;

  /// Timed exam or study-with-answers, when the caller already knows which.
  final ExamMode? initialMode;

  /// The subject's slug. Used to look up this student's measured ability for the
  /// subject, so the draw can be pitched at them.
  final String? subjectKey;

  /// The exam this sitting imitates. Sets the default clock and how the sitting
  /// is recorded; null falls back to the student choosing a board.
  final CbtExam? exam;

  /// True for Topic mode, which lets several topics be picked at once and
  /// offers the exam-type filter the website's topic picker has.
  final bool topicMode;

  /// Which collection to draw from — the junior bank for BECE.
  final String bank;

  @override
  State<ExamSetupSheet> createState() => _ExamSetupSheetState();
}

class _ExamSetupSheetState extends State<ExamSetupSheet> {
  static const _countOptions = [10, 20, 40, 60];

  /// The clocks the website offers, in minutes. Null is "no timer".
  static const _baseTimerOptions = <int?>[null, 10, 15, 20, 30, 45, 60, 90, 120];

  /// [_baseTimerOptions], with this sitting's own default folded in so the
  /// pre-selected chip is always one of the ones on screen.
  List<int?> get _timerOptions {
    final options = [..._baseTimerOptions];
    final fallback = _defaultMinutes;
    if (fallback != null && !options.contains(fallback)) {
      options
        ..add(fallback)
        ..sort((a, b) => (a ?? -1).compareTo(b ?? -1));
    }
    return options;
  }

  String _exam = ExamConfig.examBoards.first;
  final Set<String> _topics = {};
  int _count = 20;
  ExamMode _mode = ExamMode.exam;

  /// Null means "the exam's own default"; otherwise minutes.
  int? _minutes;
  bool _customTimer = false;

  String? _examTypeFilter;

  List<String> _availableTopics = const [];
  List<String> _availableExamTypes = const [];

  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialTopic != null) _topics.add(widget.initialTopic!);
    if (widget.initialMode != null) _mode = widget.initialMode!;
    _loadTopics();
    // Never offer more questions than the device actually holds — a 40-question
    // request against a 25-question pack would silently serve a short exam.
    final available = widget.subject.questionCount;
    if (available > 0 && available < _count) {
      _count = _countOptions.lastWhere((c) => c <= available, orElse: () => available);
    }
  }

  Future<void> _loadTopics() async {
    final questions = context.read<QuestionRepository>();
    final local = context.read<LocalDatabase>();

    final topics = await questions.examTopicsFor(
      widget.subject.name,
      bank: widget.bank,
    );
    if (!mounted) return;

    // The filter only makes sense against a downloaded bank — reading distinct
    // values over the network would cost the whole subject to populate a
    // dropdown.
    final examTypes = widget.subject.isDownloaded
        ? await local.distinctValues(widget.subject.name, 'exam_type')
        : const <String>[];
    if (!mounted) return;

    setState(() {
      _availableTopics = topics;
      _availableExamTypes = examTypes;

      // Realign a pre-selected topic with the bank's own spelling. Note topics
      // and bank topics are typed in two different admin screens, so their
      // capitalisation drifts — without this the chip would show no selection
      // and the sitting would quietly draw from the whole subject.
      final wanted = _topics.toList();
      _topics.clear();
      for (final topic in wanted) {
        final match = topics.where(
          (t) => t.toLowerCase() == topic.toLowerCase(),
        );
        if (match.isNotEmpty) _topics.add(match.first);
      }
    });
  }

  /// The counts worth offering: capped by what's on the device, plus the exact
  /// pack size when it falls between two options.
  List<int> get _availableCounts {
    final available = widget.subject.questionCount;
    if (available == 0) return _countOptions;
    final capped = _countOptions.where((c) => c <= available).toList();
    if (capped.isEmpty) return [available];
    if (capped.last < available && available < _countOptions.last) {
      capped.add(available);
    }
    return capped;
  }

  /// The clock for this sitting.
  ///
  /// A named exam brings its own — JAMB two hours, WAEC 45 minutes — and the
  /// student can override it. Anything else falls back to a minute a question,
  /// which is the pace the boards actually set.
  Duration? get _duration {
    if (_mode == ExamMode.practice) return null;
    if (_customTimer) {
      return _minutes == null ? null : Duration(minutes: _minutes!);
    }
    return widget.exam?.defaultDuration ?? ExamConfig.defaultDuration(_count);
  }

  /// The clock the chips show as selected before the student touches them.
  int? get _defaultMinutes =>
      (widget.exam?.defaultDuration ?? ExamConfig.defaultDuration(_count))
          .inMinutes;

  /// The stored `examType` values are WAEC and GCE; the boards renamed those
  /// papers, so the label is remapped while the stored value stays put and
  /// existing question data keeps matching. Same map as the web's
  /// `EXAM_TYPE_DISPLAY`.
  static String _examTypeLabel(String value) => switch (value.toUpperCase()) {
        'WAEC' => 'SSCE',
        'GCE' => 'A-LEVELS',
        _ => value,
      };

  Future<void> _start() async {
    // Re-read at the tap rather than trusting the disabled state: the sheet can
    // sit open across the moment a trial runs out.
    final session = context.read<SessionController>();
    if (session.access.isLocked) {
      setState(() => _error = session.access.lockNote);
      return;
    }

    setState(() {
      _starting = true;
      _error = null;
    });

    final topics = _topics.toList();
    final config = ExamConfig(
      subject: widget.subject.name,
      subjectKey: widget.subjectKey,
      // A named mode records itself as that exam; otherwise the student's board
      // choice is what goes on the record.
      exam: widget.exam?.id ?? _exam,
      topic: topics.isEmpty ? null : topics.join(', '),
      questionCount: _count,
      mode: _mode,
      duration: _duration,
    );

    final repository = context.read<QuestionRepository>();
    final learning = context.read<LearningProfileRepository>();
    final navigator = Navigator.of(context);

    List<Question> questions;
    try {
      // The profile carries the seen-question map, which is what keeps a random
      // draw from serving the same questions the student answered yesterday —
      // see `QuestionRepository.drawExam`.
      final profile = await learning.load(session.account?.uid);
      questions = await repository.drawExam(
        subject: config.subject,
        count: config.questionCount,
        topics: topics,
        examType: _examTypeFilter,
        bank: widget.bank,
        profile: profile,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = widget.subject.isDownloaded
            ? 'Could not load questions for this subject.'
            : 'You are offline and this subject is not downloaded yet. '
                'Download it first, then practise anywhere.';
      });
      return;
    }

    if (!mounted) return;

    if (questions.isEmpty) {
      setState(() {
        _starting = false;
        _error = topics.isEmpty
            ? 'No questions are available for this subject yet.'
            : 'No questions found under '
                '${topics.length == 1 ? '"${topics.first}"' : 'those topics'}. '
                'Try All topics, or clear the filters.';
      });
      return;
    }

    // The sheet closes before the runner opens, so Back from the exam lands on
    // the practice list rather than re-opening this sheet.
    navigator.pop();
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ExamScreen(
          // The drawn count is what the paper actually holds; a short bank must
          // not leave the progress bar reporting against questions that aren't
          // there.
          config: config.copyWith(questionCount: questions.length),
          questions: questions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // The whole state, not just the flag: a student whose free trial ran out
    // has never paid, so telling them their payment "expired" is wrong.
    final access = context.select<SessionController, AccessState>(
      (s) => s.access,
    );
    final locked = access.isLocked;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Tokens.s5,
          right: Tokens.s5,
          bottom: Tokens.s6 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.subject.name, style: text.headlineSmall),
              const SizedBox(height: Tokens.s1),
              Text(
                widget.subject.isDownloaded
                    ? '${widget.subject.questionCount} questions on this device'
                    : 'Not downloaded — this sitting needs a connection',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Tokens.s5),

              // Only asked when the mode doesn't already name the exam — a WAEC
              // sitting is a WAEC sitting.
              if (widget.exam == null) ...[
                const _Label('Exam board'),
                _ChipRow<String>(
                  values: ExamConfig.examBoards,
                  selected: _exam,
                  labelOf: (v) => v,
                  onSelected: (v) => setState(() => _exam = v),
                ),
                const SizedBox(height: Tokens.s5),
              ],

              if (_availableTopics.isNotEmpty) ...[
                _Label(
                  widget.topicMode
                      ? 'Topics (${_topics.length} selected)'
                      : 'Topic',
                ),
                if (widget.topicMode)
                  // Topic mode is multi-select, exactly as the web's checklist
                  // is: revising two related topics together is the point of it.
                  Wrap(
                    spacing: Tokens.s2,
                    runSpacing: Tokens.s2,
                    children: [
                      for (final topic in _availableTopics)
                        FilterChip(
                          label: Text(topic),
                          selected: _topics.contains(topic),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _topics.add(topic);
                            } else {
                              _topics.remove(topic);
                            }
                          }),
                        ),
                    ],
                  )
                else
                  _ChipRow<String?>(
                    values: [null, ..._availableTopics],
                    selected: _topics.firstOrNull,
                    labelOf: (v) => v ?? 'All topics',
                    onSelected: (v) => setState(() {
                      _topics
                        ..clear()
                        ..addAll(v == null ? const <String>[] : [v]);
                    }),
                  ),
                const SizedBox(height: Tokens.s5),
              ],

              // The website offers these two on its topic picker, driven by
              // whatever the bank actually holds.
              if (widget.topicMode && _availableExamTypes.isNotEmpty) ...[
                const _Label('Exam type'),
                _ChipRow<String?>(
                  values: [null, ..._availableExamTypes],
                  selected: _examTypeFilter,
                  labelOf: (v) => v == null ? 'All' : _examTypeLabel(v),
                  onSelected: (v) => setState(() => _examTypeFilter = v),
                ),
                const SizedBox(height: Tokens.s5),
              ],
              // No difficulty chips. The Easy/Medium/Hard labels came in
              // inconsistently across uploads, so filtering on one handed the
              // student a paper that did not match what the chip promised.
              const _Label('Questions'),
              _ChipRow<int>(
                values: _availableCounts,
                selected: _count,
                labelOf: (v) => '$v',
                onSelected: (v) => setState(() => _count = v),
              ),
              const SizedBox(height: Tokens.s5),

              const _Label('Time limit'),
              _ChipRow<int?>(
                values: _timerOptions,
                selected: _customTimer ? _minutes : _defaultMinutes,
                labelOf: (v) => v == null ? 'No timer' : '$v min',
                onSelected: (v) => setState(() {
                  _customTimer = true;
                  _minutes = v;
                }),
              ),
              const SizedBox(height: Tokens.s5),

              const _Label('Mode'),
              _ModeCard(
                selected: _mode == ExamMode.exam,
                title: 'Timed exam',
                detail: _duration == null
                    ? 'Real conditions — no clock, score at the end.'
                    : 'Real conditions — ${_duration!.inMinutes} minutes, '
                        'score at the end.',
                icon: Icons.timer_outlined,
                onTap: () => setState(() => _mode = ExamMode.exam),
              ),
              const SizedBox(height: Tokens.s3),
              _ModeCard(
                selected: _mode == ExamMode.practice,
                title: 'Practice',
                detail: 'No clock, and the answer is explained as you go.',
                icon: Icons.school_outlined,
                onTap: () => setState(() => _mode = ExamMode.practice),
              ),

              if (_error != null) ...[
                const SizedBox(height: Tokens.s5),
                MessageBanner(message: _error!),
              ],

              if (locked) ...[
                const SizedBox(height: Tokens.s5),
                MessageBanner(
                  message: access.lockNote,
                  tone: MessageTone.info,
                ),
              ],

              const SizedBox(height: Tokens.s6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _starting || locked ? null : _start,
                  icon: _starting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    _starting ? 'Preparing your questions…' : 'Start',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.s2),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
}

/// Horizontally scrolling single-select chips.
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: values.length,
          separatorBuilder: (_, _) => const SizedBox(width: Tokens.s2),
          itemBuilder: (context, i) {
            final value = values[i];
            return ChoiceChip(
              label: Text(labelOf(value)),
              selected: value == selected,
              onSelected: (_) => onSelected(value),
            );
          },
        ),
      );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.title,
    required this.detail,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(Tokens.rMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        child: Container(
          padding: const EdgeInsets.all(Tokens.s4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.rMd),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? scheme.onPrimaryContainer : scheme.primary,
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected ? scheme.onPrimaryContainer : null,
                      ),
                    ),
                    Text(
                      detail,
                      style: text.bodySmall?.copyWith(
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
