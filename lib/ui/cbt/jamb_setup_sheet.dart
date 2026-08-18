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

/// Builds a UTME paper.
///
/// Port of the `mode === 'jamb'` branch of the web's SetupScreen: English is
/// compulsory and carries 60 questions; the student picks up to three more at 40
/// each, and the whole paper runs for two hours. That shape is the exam, not a
/// preference, which is why none of it is adjustable here.
Future<void> showJambSetupSheet(
  BuildContext context,
  List<Subject> subjects,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => JambSetupSheet(subjects: subjects),
    );

class JambSetupSheet extends StatefulWidget {
  const JambSetupSheet({super.key, required this.subjects});

  final List<Subject> subjects;

  @override
  State<JambSetupSheet> createState() => _JambSetupSheetState();
}

class _JambSetupSheetState extends State<JambSetupSheet> {
  /// What the web pre-selects, so a student who just wants to sit a paper can
  /// press Start straight away.
  static const _defaultPicks = ['mathematics', 'physics', 'chemistry'];

  late Set<String> _picked;
  bool _starting = false;
  String? _error;

  /// English is compulsory in UTME and is never in the optional list.
  static const _englishKey = 'english';

  @override
  void initState() {
    super.initState();
    final available = widget.subjects.map((s) => s.key).toSet();
    _picked = _defaultPicks.where(available.contains).toSet();
  }

  Subject? get _english =>
      widget.subjects.where((s) => s.key == _englishKey).firstOrNull;

  List<Subject> get _optional =>
      widget.subjects.where((s) => s.key != _englishKey).toList();

  void _toggle(Subject subject) {
    setState(() {
      if (_picked.contains(subject.key)) {
        _picked.remove(subject.key);
      } else if (_picked.length < 3) {
        _picked.add(subject.key);
      }
    });
  }

  Future<void> _start() async {
    // Re-read at the tap: the sheet can sit open across the moment a trial ends.
    final session = context.read<SessionController>();
    if (session.access.isLocked) {
      setState(() => _error = session.access.lockNote);
      return;
    }
    if (_picked.isEmpty) {
      setState(
        () => _error = 'Pick at least one subject alongside English Language.',
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

      // English first, then the chosen three in the order they were picked —
      // the same running order as the real paper.
      final english = _english;
      final requests = <SectionRequest>[
        if (english != null)
          // Comprehension and cloze come as whole passages, pinned where the
          // real paper puts them; the rest of English is drawn at random.
          SectionRequest.of(
            english,
            CbtExam.jambEnglishCount,
            passages: CbtExam.jambEnglishPassages,
          ),
        for (final key in _picked)
          ...widget.subjects
              .where((s) => s.key == key)
              .map((s) => SectionRequest.of(s, CbtExam.jambSubjectCount)),
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
        // The primary subject the sitting is recorded against, which for a UTME
        // paper is English — the one every candidate takes.
        subject: paper.sections.first.name,
        subjectKey: paper.sections.first.key,
        exam: CbtExam.jamb.id,
        questionCount: paper.total,
        mode: ExamMode.exam,
        duration: CbtExam.jamb.defaultDuration,
        sections: paper.sections,
        // Only a full four-subject paper is out of 400; a short one would report
        // a score the student could not compare to anything.
        scoresOutOf400: paper.sections.length == 4,
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
    final english = _english;
    final total = (english == null ? 0 : CbtExam.jambEnglishCount) +
        _picked.length * CbtExam.jambSubjectCount;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s5,
          Tokens.s2,
          Tokens.s5,
          Tokens.s5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'JAMB / UTME',
              style: GoogleFonts.fraunces(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$total questions · 2 hours · English plus your three subjects',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Tokens.s5),

            if (english != null) ...[
              _SectionLabel('English Language (required)'),
              const SizedBox(height: Tokens.s2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.s3,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(Tokens.rSm),
                ),
                child: Row(
                  children: [
                    Icon(english.icon, size: 16, color: english.color),
                    const SizedBox(width: Tokens.s2),
                    Expanded(
                      child: Text(
                        english.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '${CbtExam.jambEnglishCount} qs',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: Tokens.s2),
                    Icon(
                      Icons.lock_rounded,
                      size: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Tokens.s5),
            ],

            _SectionLabel('Pick up to 3 more (${_picked.length}/3)'),
            const SizedBox(height: Tokens.s2),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: Tokens.s2,
                  runSpacing: Tokens.s2,
                  children: [
                    for (final subject in _optional)
                      _SubjectChip(
                        subject: subject,
                        selected: _picked.contains(subject.key),
                        // Greyed rather than hidden once three are chosen: the
                        // student should still see what else exists.
                        enabled: _picked.contains(subject.key) ||
                            _picked.length < 3,
                        onTap: () => _toggle(subject),
                      ),
                  ],
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: Tokens.s4),
              MessageBanner(message: _error!),
            ],

            const SizedBox(height: Tokens.s5),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _starting ? null : _start,
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
                  _starting ? 'Building your paper…' : 'Start Exam',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
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
