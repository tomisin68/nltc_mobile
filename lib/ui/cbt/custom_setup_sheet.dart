import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/learning_profile_repository.dart';
import '../../data/repositories/question_repository.dart';
import '../../domain/models/exam_config.dart';
import '../../domain/models/subject.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/message_banner.dart';
import '../exam/exam_screen.dart';

/// Builds a paper the student designs themselves.
///
/// Port of the web's Custom CBT Builder (`components/exam/CustomExamBuilder.jsx`):
/// as many subjects as they like, their own question count for each one, and
/// their own clock — a preset, no timer at all, or a figure they type.
///
/// Deliberately has no topic picker. Topic mode already owns topic-filtered
/// practice, and letting a custom paper narrow by topic too would make "custom"
/// mean two different things depending on which screen you came from.
Future<void> showCustomSetupSheet(
  BuildContext context,
  List<Subject> subjects,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomSetupSheet(subjects: subjects),
    );

class CustomSetupSheet extends StatefulWidget {
  const CustomSetupSheet({super.key, required this.subjects});

  final List<Subject> subjects;

  @override
  State<CustomSetupSheet> createState() => _CustomSetupSheetState();
}

class _CustomSetupSheetState extends State<CustomSetupSheet> {
  /// Question counts a subject may carry, and the nudge the steppers move by.
  static const _minQuestions = 1;
  static const _maxQuestions = 100;
  static const _defaultQuestions = 20;
  static const _step = 5;

  /// How many subjects one paper may hold. Each one is its own question draw,
  /// so this is a real cost, not a style choice.
  static const _maxSubjects = 8;

  /// The clocks offered as one tap, in minutes. Null is "no timer".
  static const _timePresets = <int>[15, 30, 45, 60, 90, 120];
  static const _minMinutes = 1;
  static const _maxMinutes = 300;

  /// Chosen subjects in the order they were picked — that is the order the
  /// sections run in, exactly as English leads a UTME paper.
  final List<String> _order = [];
  final Map<String, int> _counts = {};

  /// Null means no timer. Only meaningful once [_timed] is true.
  int? _minutes = 60;
  bool _timed = true;

  /// True once the student opens the "My own time" field, so a typed 30 isn't
  /// mistaken for the 30-minute preset and the field yanked out from under them.
  bool _ownTime = false;

  final _ownTimeController = TextEditingController();

  bool _starting = false;
  String? _error;

  @override
  void dispose() {
    _ownTimeController.dispose();
    super.dispose();
  }

  int get _total => _order.fold(0, (sum, key) => sum + (_counts[key] ?? 0));

  Subject _subjectFor(String key) =>
      widget.subjects.firstWhere((s) => s.key == key);

  void _toggle(Subject subject) {
    setState(() {
      if (_order.remove(subject.key)) {
        _counts.remove(subject.key);
        return;
      }
      if (_order.length >= _maxSubjects) return;
      _order.add(subject.key);
      _counts[subject.key] = _defaultQuestions;
    });
  }

  void _setCount(String key, int count) => setState(
        () => _counts[key] = count.clamp(_minQuestions, _maxQuestions),
      );

  Future<void> _start() async {
    // Re-read at the tap: the sheet can sit open across the moment a trial ends.
    final session = context.read<SessionController>();
    if (session.access.isLocked) {
      setState(() => _error = session.access.lockNote);
      return;
    }
    if (_order.isEmpty) {
      setState(
        () => _error = 'Pick at least one subject for your paper.',
      );
      return;
    }

    setState(() {
      _starting = true;
      _error = null;
    });

    final questions = context.read<QuestionRepository>();
    final learning = context.read<LearningProfileRepository>();
    final navigator = Navigator.of(context);

    try {
      // The student's ability estimate, so each subject draws questions pitched
      // where they will actually learn something.
      final profile = await learning.load(session.account?.uid);

      final requests = [
        for (final key in _order)
          SectionRequest.of(_subjectFor(key), _counts[key] ?? _defaultQuestions),
      ];
      final paper = await questions.drawPaper(requests, profile: profile);

      if (!mounted) return;
      if (paper.isEmpty) {
        setState(() {
          _starting = false;
          _error = 'No questions are available for those subjects yet. '
              'Download them for offline use, or ask your admin to add some.';
        });
        return;
      }

      final config = ExamConfig(
        // The sitting is recorded against the first subject the student chose,
        // which is the same rule the web uses for a multi-subject paper.
        subject: paper.sections.first.name,
        subjectKey: paper.sections.first.key,
        exam: CbtExam.custom.id,
        questionCount: paper.total,
        mode: ExamMode.exam,
        // Null clock is a real choice here, not a missing one — a custom paper
        // with no timer is untimed practice under exam conditions.
        duration: _timed && _minutes != null ? Duration(minutes: _minutes!) : null,
        sections: paper.sections,
      );

      navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ExamScreen(config: config, questions: paper.questions),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Could not load the questions. Check your connection, or '
            'download these subjects for offline use.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final atLimit = _order.length >= _maxSubjects;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Tokens.s5,
          right: Tokens.s5,
          bottom: Tokens.s5 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          // The sheet grows with its content but never past the viewport, so
          // the scroll view inside it always has somewhere to scroll to.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Custom CBT',
                style: GoogleFonts.fraunces(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Choose your subjects, how many questions each one carries, and '
                'how long you get.',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Tokens.s5),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SectionLabel(
                        'Subjects',
                        trailing: '${_order.length}/$_maxSubjects chosen',
                      ),
                      const SizedBox(height: Tokens.s2),
                      Wrap(
                        spacing: Tokens.s2,
                        runSpacing: Tokens.s2,
                        children: [
                          for (final subject in widget.subjects)
                            _SubjectChip(
                              subject: subject,
                              selected: _order.contains(subject.key),
                              // Greyed rather than hidden at the limit: the
                              // student should still see what else exists.
                              enabled: _order.contains(subject.key) || !atLimit,
                              onTap: () => _toggle(subject),
                            ),
                        ],
                      ),
                      const SizedBox(height: Tokens.s5),

                      const _SectionLabel('Questions per subject'),
                      const SizedBox(height: Tokens.s2),
                      if (_order.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: Tokens.s3,
                            vertical: Tokens.s4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Tokens.rSm),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Text(
                            'Pick a subject above and it will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        for (final key in _order)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Tokens.s2),
                            child: _CountRow(
                              subject: _subjectFor(key),
                              count: _counts[key] ?? _defaultQuestions,
                              min: _minQuestions,
                              max: _maxQuestions,
                              onLess: () {
                                final current = _counts[key] ?? _defaultQuestions;
                                _setCount(
                                  key,
                                  current <= _step
                                      ? _minQuestions
                                      // Snap to the step rather than sliding off
                                      // it, so 27 goes to 25 and not 22.
                                      : (current - 1) ~/ _step * _step,
                                );
                              },
                              onMore: () {
                                final current = _counts[key] ?? _defaultQuestions;
                                _setCount(key, (current ~/ _step + 1) * _step);
                              },
                              onRemove: () => _toggle(_subjectFor(key)),
                            ),
                          ),
                      const SizedBox(height: Tokens.s5),

                      const _SectionLabel('Time limit'),
                      const SizedBox(height: Tokens.s2),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          ChoiceChip(
                            label: const Text('No timer'),
                            selected: !_timed,
                            onSelected: (_) => setState(() {
                              _timed = false;
                              _ownTime = false;
                            }),
                          ),
                          for (final minutes in _timePresets)
                            ChoiceChip(
                              label: Text('$minutes min'),
                              selected:
                                  _timed && !_ownTime && _minutes == minutes,
                              onSelected: (_) => setState(() {
                                _timed = true;
                                _ownTime = false;
                                _minutes = minutes;
                              }),
                            ),
                          ChoiceChip(
                            avatar: Icon(
                              Icons.edit_rounded,
                              size: 15,
                              color: _ownTime
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                            label: const Text('My own time'),
                            selected: _timed && _ownTime,
                            onSelected: (_) => setState(() {
                              _timed = true;
                              _ownTime = true;
                              // Seed with a minute a question — the pace the
                              // boards actually set — rather than a blank box.
                              _minutes = (_total == 0 ? _defaultQuestions : _total)
                                  .clamp(_minMinutes, _maxMinutes);
                              _ownTimeController.text = '$_minutes';
                            }),
                          ),
                        ],
                      ),
                      if (_timed && _ownTime) ...[
                        const SizedBox(height: Tokens.s3),
                        Row(
                          children: [
                            SizedBox(
                              width: 110,
                              child: TextField(
                                controller: _ownTimeController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Minutes',
                                  isDense: true,
                                ),
                                onChanged: (value) {
                                  final parsed = int.tryParse(value.trim());
                                  setState(
                                    () => _minutes = parsed?.clamp(
                                      _minMinutes,
                                      _maxMinutes,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: Tokens.s3),
                            Expanded(
                              child: Text(
                                'Anything from $_minMinutes to $_maxMinutes '
                                'minutes.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: Tokens.s3),
                      Text(
                        'Real papers allow roughly a minute a question — that '
                        'would be ${_total == 0 ? _defaultQuestions : _total} '
                        'min for this one.',
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: Tokens.s4),
                        MessageBanner(message: _error!),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: Tokens.s4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _starting || _order.isEmpty ? null : _start,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _starting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    _starting
                        ? 'Building your paper…'
                        : _order.isEmpty
                            ? 'Start My Exam'
                            : 'Start My Exam ($_total questions)',
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          Text(
            trailing!,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// One chosen subject and the questions it carries.
class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.subject,
    required this.count,
    required this.min,
    required this.max,
    required this.onLess,
    required this.onMore,
    required this.onRemove,
  });

  final Subject subject;
  final int count;
  final int min;
  final int max;
  final VoidCallback onLess;
  final VoidCallback onMore;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(Tokens.s3, 6, 4, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.rSm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(subject.icon, size: 16, color: subject.color),
          const SizedBox(width: Tokens.s2),
          Expanded(
            child: Text(
              subject.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          IconButton(
            onPressed: count <= min ? null : onLess,
            icon: const Icon(Icons.remove_rounded, size: 18),
            tooltip: 'Fewer ${subject.name} questions',
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ),
          IconButton(
            onPressed: count >= max ? null : onMore,
            icon: const Icon(Icons.add_rounded, size: 18),
            tooltip: 'More ${subject.name} questions',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 17),
            tooltip: 'Remove ${subject.name}',
            visualDensity: VisualDensity.compact,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _SubjectChip extends StatelessWidget {
  const _SubjectChip({
    required this.subject,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Subject subject;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: selected
            ? subject.color.withValues(alpha: 0.14)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: selected ? subject.color : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(subject.icon, size: 14, color: subject.color),
                const SizedBox(width: 6),
                Text(
                  subject.name,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.check_rounded, size: 13, color: subject.color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
