import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/study_note_repository.dart';
import '../../data/repositories/subject_repository.dart';
import '../../data/services/mission_signals.dart';
import '../../domain/models/study_note.dart';
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
import '../shell/dashboard_sidebar.dart' show DashboardSidebar;

/// Study notes: subject grid → topic list → note reader.
///
/// Port of `src/pages/dashboard/StudyNotesView.jsx`. The three levels are one
/// screen with its own back stack rather than three routes, matching the web's
/// conditional render — so backing out of a note returns to the topic list with
/// its scroll position intact.
class StudyNotesScreen extends StatefulWidget {
  const StudyNotesScreen({super.key});

  @override
  State<StudyNotesScreen> createState() => _StudyNotesScreenState();
}

class _StudyNotesScreenState extends State<StudyNotesScreen> {
  Subject? _subject;
  NoteTopic? _topic;

  List<Subject> _subjects = const [];
  List<NoteTopic> _topics = const [];
  bool _loadingTopics = false;

  SubjectCategory get _category =>
      DashboardSidebar.isJuniorStudent(context.read<SessionController>().profile)
          ? SubjectCategory.junior
          : SubjectCategory.senior;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    final subjects =
        await context.read<SubjectRepository>().decorated(_category);
    if (!mounted) return;
    setState(() => _subjects = subjects);
  }

  Future<void> _openSubject(Subject subject) async {
    setState(() {
      _subject = subject;
      _topic = null;
      _topics = const [];
      _loadingTopics = true;
    });

    final topics = await context.read<StudyNoteRepository>().topics(
      subjectName: subject.name,
      category: _category,
    );
    if (!mounted) return;
    setState(() {
      _topics = topics;
      _loadingTopics = false;
    });
  }

  void _openTopic(NoteTopic topic) {
    setState(() => _topic = topic);
    // Mission credit only for a topic that actually has something to read.
    if (topic.hasNote) {
      context.read<MissionSignals>().set(
        'study_notes',
        context.read<SessionController>().account?.uid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_topic != null) {
      return _NoteReader(
        subject: _subject!,
        topic: _topic!,
        onBack: () => setState(() => _topic = null),
        onTakeTest: _takeTest,
      );
    }
    if (_subject != null) return _topicList();
    return _subjectGrid();
  }

  Widget _subjectGrid() => ListView(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s4,
          0,
          Tokens.s4,
          Tokens.s10,
        ),
        children: [
          const PageHeader(
            title: 'Study Notes',
            subtitle: 'Pick a subject to browse topic-by-topic notes from your '
                'teachers.',
          ),
          AppCard(
            child: _subjects.isEmpty
                ? const SkeletonListItem(lines: 2)
                : SubjectGrid(
                    subjects: _subjects,
                    caption: 'Notes',
                    onTap: _openSubject,
                  ),
          ),
        ],
      );

  Widget _topicList() {
    final scheme = Theme.of(context).colorScheme;
    final subject = _subject!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
      children: [
        _BackLink(
          label: 'Subjects',
          onTap: () => setState(() => _subject = null),
        ),
        PageHeader(
          title: subject.name,
          subtitle: 'Select a topic to read its study notes.',
          leading: Icon(subject.icon, size: 20, color: subject.color),
        ),
        if (_loadingTopics)
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < 4; i++)
                  const SkeletonListItem(lines: 1, showAvatar: false),
              ],
            ),
          )
        else if (_topics.isEmpty)
          const AppCard(
            child: EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'No topics yet',
              message: 'Ask your admin to add questions with a Topic tag for '
                  'this subject first.',
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _topics.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: scheme.outlineVariant),
                  _TopicRow(
                    topic: _topics[i],
                    accent: subject.color,
                    onTap: () => _openTopic(_topics[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// "Take a Test on This Topic" — 20 questions drawn from the bank.
  ///
  /// The web navigates to `/cbt?mode=topic&…`; here the same intent opens the
  /// app's exam setup sheet with the subject and topic already chosen, so the
  /// student can still pick a length before starting.
  void _takeTest() {
    final subject = _subject;
    final topic = _topic;
    if (subject == null || topic == null) return;

    final practice = context.read<PracticeController>();
    showExamSetupSheet(
      context,
      practice.entryFor(subject.name),
      initialTopic: topic.topic,
    );
  }
}

/// `.btn-outline.btn-xs` used as a breadcrumb back up one level.
class _BackLink extends StatelessWidget {
  const _BackLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.s3),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 15),
            label: Text(label),
          ),
        ),
      );
}

/// `.sched-row` — one topic, with its subject-coloured spine.
class _TopicRow extends StatelessWidget {
  const _TopicRow({
    required this.topic,
    required this.accent,
    required this.onTap,
  });

  final NoteTopic topic;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Opacity(
        // A topic with no note yet is dimmed but still tappable — it leads to the
        // "coming soon" note and the option to practise it anyway.
        opacity: topic.hasNote ? 1 : 0.6,
        child: Container(
          constraints: const BoxConstraints(minHeight: Tokens.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s4,
            vertical: Tokens.s3,
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 22,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Text(
                  topic.topic,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (!topic.hasNote) ...[
                const AppBadge(label: 'Coming soon'),
                const SizedBox(width: Tokens.s2),
              ],
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The note itself, rendered from the admin's HTML.
class _NoteReader extends StatelessWidget {
  const _NoteReader({
    required this.subject,
    required this.topic,
    required this.onBack,
    required this.onTakeTest,
  });

  final Subject subject;
  final NoteTopic topic;
  final VoidCallback onBack;
  final VoidCallback onTakeTest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
      children: [
        _BackLink(label: subject.name, onTap: onBack),
        PageHeader(title: topic.topic, subtitle: subject.name),
        AppCard(
          child: topic.hasNote
              // The admin's rich-text editor emits HTML. Only the safe subset is
              // rendered: no scripts, no iframes, no remote CSS — the renderer
              // supports inline formatting, lists, tables and images, which is
              // everything the editor can produce.
              ? HtmlWidget(
                  topic.note!.content,
                  textStyle: TextStyle(
                    fontSize: 14.5,
                    height: 1.7,
                    color: scheme.onSurface,
                  ),
                  // Anything not on the allowlist is dropped rather than rendered.
                  customWidgetBuilder: (element) =>
                      const {'script', 'iframe', 'object', 'embed', 'form'}
                              .contains(element.localName)
                          ? const SizedBox.shrink()
                          : null,
                )
              : const EmptyState(
                  icon: Icons.hourglass_empty_rounded,
                  title: 'Notes coming soon',
                  message: "Your teachers haven't written notes for this topic "
                      'yet — check back later.',
                ),
        ),
        const SizedBox(height: Tokens.s4),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s4,
            vertical: Tokens.s6,
          ),
          child: Column(
            children: [
              Text(
                'Ready to test what you just learned?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onTakeTest,
                icon: const Icon(Icons.edit_rounded, size: 17),
                label: const Text('Take a Test on This Topic'),
              ),
              const SizedBox(height: 10),
              Text(
                '20 random questions from the question bank on '
                '${topic.topic}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
