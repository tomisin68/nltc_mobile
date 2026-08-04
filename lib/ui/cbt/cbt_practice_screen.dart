import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/exam_result_repository.dart';
import '../../data/repositories/subject_repository.dart';
import '../../domain/models/exam_config.dart';
import '../../domain/models/exam_result.dart';
import '../../domain/models/subject.dart';
import '../core/state/practice_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/skeleton.dart';
import '../core/widgets/subject_grid.dart';
import '../practice/exam_setup_sheet.dart';
import '../practice/practice_screen.dart';
import 'jamb_setup_sheet.dart';
import 'widgets/history_list.dart';
import 'widgets/mode_card.dart';

/// The exam modes a senior student can pick.
///
/// Straight from `CBTPracticeView.jsx` — same keys, same descriptions, so the
/// two products describe the same thing the same way.
enum CbtMode {
  jamb('JAMB', Icons.adjust_rounded, '4 subjects · 180 qs · 2 hrs', CbtExam.jamb),
  waec('WAEC', Icons.assignment_rounded, '1 subject · 45 min', CbtExam.waec),
  study(
    'Study Mode',
    Icons.menu_book_rounded,
    'Instant answers & explanations',
    CbtExam.study,
  ),
  postUtme(
    'Post UTME',
    Icons.account_balance_rounded,
    '1 subject · 30 min',
    CbtExam.postUtme,
  ),
  topic(
    'Topic',
    Icons.place_rounded,
    'Practice by specific topics',
    CbtExam.topic,
  );

  const CbtMode(this.label, this.icon, this.description, this.exam);

  final String label;
  final IconData icon;
  final String description;

  /// What the sitting is recorded as, and where its default clock comes from.
  final CbtExam exam;
}

/// CBT Practice.
///
/// Port of `src/pages/dashboard/CBTPracticeView.jsx`: an exam-mode selector, a
/// study-by-subject grid, and the student's exam history.
///
/// One addition the website cannot have: a link to the offline subject manager.
/// Downloaded question banks are what let a sitting run with no signal, which is
/// the whole point of the app on a Nigerian data plan.
class CbtPracticeScreen extends StatefulWidget {
  const CbtPracticeScreen({super.key});

  @override
  State<CbtPracticeScreen> createState() => _CbtPracticeScreenState();
}

class _CbtPracticeScreenState extends State<CbtPracticeScreen> {
  CbtMode _mode = CbtMode.jamb;
  List<Subject> _subjects = const [];
  List<ExamResult> _history = const [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Both repositories and the uid are read before the first await — this method
    // spans two round trips, and reaching back into the tree afterwards is what
    // `use_build_context_synchronously` warns about.
    final subjectRepository = context.read<SubjectRepository>();
    final resultRepository = context.read<ExamResultRepository>();
    final uid = context.read<SessionController>().account?.uid;

    final subjects = await subjectRepository.decorated(SubjectCategory.senior);
    if (!mounted) return;
    setState(() => _subjects = subjects);

    if (uid == null) {
      setState(() => _loadingHistory = false);
      return;
    }
    final history = await resultRepository.recent(uid);
    if (!mounted) return;
    setState(() {
      _history = history;
      _loadingHistory = false;
    });
  }

  /// Starts the chosen mode.
  ///
  /// The web pushes `/cbt?mode=…` and asks for the subject on the next screen;
  /// the app opens the setup sheet, which is the same step in one fewer tap.
  void _start() {
    final practice = context.read<PracticeController>();
    final subjects = practice.visible;

    if (subjects.isEmpty && _subjects.isEmpty) {
      // No catalogue yet — send them to the subject list, which is where the
      // download (and the error, if there is one) actually lives.
      _openOfflineManager();
      return;
    }

    final catalogue = _subjects.isEmpty
        ? Subjects.decorate(subjects.map((s) => s.name))
        : _subjects;

    // JAMB is a four-subject paper, not a subject with settings, so it gets its
    // own sheet rather than the single-subject one.
    if (_mode == CbtMode.jamb) {
      showJambSetupSheet(context, catalogue);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _SubjectPickerSheet(
        subjects: catalogue,
        mode: _mode,
        onPick: (subject) {
          Navigator.of(sheetContext).pop();
          showExamSetupSheet(
            context,
            practice.entryFor(subject.name),
            subjectKey: subject.key,
            exam: _mode.exam,
            initialMode:
                _mode == CbtMode.study ? ExamMode.practice : ExamMode.exam,
            topicMode: _mode == CbtMode.topic,
          );
        },
      ),
    );
  }

  void _openOfflineManager() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PracticeScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async {
        final uid = context.read<SessionController>().account?.uid;
        if (uid != null) context.read<ExamResultRepository>().invalidate(uid);
        await _load();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s4,
          0,
          Tokens.s4,
          Tokens.s10,
        ),
        children: [
          const PageHeader(
            title: 'CBT Practice',
            subtitle: 'Simulate real exam conditions with timed sessions.',
          ),

          // ── Exam mode ──
          AppCard(
            title: 'Exam Mode',
            titleIcon: Icons.settings_rounded,
            child: Column(
              children: [
                ModeGrid(
                  children: [
                    for (final mode in CbtMode.values)
                      ModeCard(
                        icon: mode.icon,
                        name: mode.label,
                        description: mode.description,
                        selected: _mode == mode,
                        onTap: () => setState(() => _mode = mode),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _start,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text('Start ${_mode.label} Session'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s4),

          // ── Study by subject ──
          AppCard(
            title: 'Study by Subject',
            titleIcon: Icons.menu_book_rounded,
            child: _subjects.isEmpty
                ? const SkeletonListItem(lines: 2)
                : SubjectGrid(
                    subjects: _subjects,
                    caption: 'Study',
                    // Study mode goes straight in — the web sets `autostart=1`
                    // on these tiles for the same reason.
                    onTap: (subject) => showExamSetupSheet(
                      context,
                      context.read<PracticeController>().entryFor(subject.name),
                      initialMode: ExamMode.practice,
                    ),
                  ),
          ),
          const SizedBox(height: Tokens.s4),

          // ── Offline subjects (app only) ──
          AppCard(
            onTap: _openOfflineManager,
            child: Row(
              children: [
                Icon(
                  Icons.download_for_offline_rounded,
                  size: 22,
                  color: scheme.primary,
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Offline subjects',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Download a subject once and sit exams on it with no '
                        'connection at all.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s4),

          // ── History ──
          AppCard(
            title: 'Exam History',
            titleIcon: Icons.history_rounded,
            padding: EdgeInsets.zero,
            headerTrailing: _history.isEmpty
                ? null
                : Text(
                    '${_history.length} sessions',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
            child: _loadingHistory
                ? const SkeletonTable()
                : _history.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: Tokens.s5),
                        child: EmptyState(
                          icon: Icons.assignment_outlined,
                          title: 'No sessions yet',
                          message:
                              'Start your first CBT, quiz, or quick test above!',
                        ),
                      )
                    : HistoryList(results: _history),
          ),
        ],
      ),
    );
  }
}

/// Which subject the chosen mode applies to.
///
/// The web asks for this on its own setup screen; on a phone a sheet keeps the
/// mode selection visible behind it.
class _SubjectPickerSheet extends StatelessWidget {
  const _SubjectPickerSheet({
    required this.subjects,
    required this.mode,
    required this.onPick,
  });

  final List<Subject> subjects;
  final CbtMode mode;
  final void Function(Subject) onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
              '${mode.label} — pick a subject',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: Tokens.s4),
            Flexible(
              child: SingleChildScrollView(
                child: SubjectGrid(
                  subjects: subjects,
                  caption: mode.label,
                  onTap: onPick,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
