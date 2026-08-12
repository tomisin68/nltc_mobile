import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/study_note_repository.dart';
import '../../data/repositories/subject_repository.dart';
import '../../data/services/mission_signals.dart';
import '../../data/services/notes_reader.dart';
import '../../domain/models/study_note.dart';
import '../../domain/models/subject.dart';
import '../core/state/practice_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/skeleton.dart';
import '../core/widgets/in_app_browser.dart';
import '../core/widgets/subject_grid.dart';
import '../practice/exam_setup_sheet.dart';
import 'widgets/note_document.dart';
import 'widgets/note_html.dart';
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

  /// Topics published as whole HTML documents in the standalone reader. Empty
  /// for every subject that has none, and empty when the site can't be reached
  /// — either way this view falls back to exactly what Firestore holds.
  List<ReaderTopic> _readerTopics = const [];


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
      _readerTopics = const [];
      _loadingTopics = true;
    });

    final reader = context.read<NotesReaderService>();
    final topics = await context.read<StudyNoteRepository>().topics(
      subjectName: subject.name,
      category: _category,
    );
    if (!mounted) return;
    setState(() {
      _topics = topics;
      _loadingTopics = false;
    });

    // After the list, not with it: the illustrated notes are a bonus and must
    // never hold up the topics the student came for.
    if (subject.name != NotesReaderService.readerSubject) return;
    final published = await reader.manifest();
    if (!mounted || _subject?.name != subject.name) return;
    setState(() => _readerTopics = published);
  }

  /// Opens the standalone reader, on [entry] when there is one.
  ///
  /// Pushed as an in-app browser rather than drawn inside this view, the way
  /// the blog and the legal documents are: that gives it the hardware back
  /// button — walking the reader's own topic history first, then returning
  /// here — which a WebView embedded in a dashboard view does not get.
  void _openReader(ReaderTopic? entry) {
    openInAppBrowser(
      context,
      NotesReaderService.url(order: entry?.order),
      title: entry?.title ?? 'Illustrated notes',
    );
    context.read<MissionSignals>().set(
      'study_notes',
      context.read<SessionController>().account?.uid,
    );
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
        reader: NotesReaderService.find(_readerTopics, _topic!.topic),
        onBack: () => setState(() => _topic = null),
        onTakeTest: _takeTest,
        onOpenReader: _openReader,
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
                  Builder(
                    builder: (_) {
                      final entry =
                          NotesReaderService.find(_readerTopics, _topics[i].topic);
                      // With no Firestore note behind it, the illustrated file
                      // *is* the note — open it rather than showing "coming
                      // soon" for a topic that has in fact been written.
                      final readerOnly = entry != null && !_topics[i].hasNote;
                      return _TopicRow(
                        topic: _topics[i],
                        accent: subject.color,
                        hasReader: entry != null,
                        opensReader: readerOnly,
                        onTap: () => readerOnly
                            ? _openReader(entry)
                            : _openTopic(_topics[i]),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        if (_readerTopics.isNotEmpty) ...[
          const SizedBox(height: Tokens.s4),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s4,
              vertical: Tokens.s5,
            ),
            child: Column(
              children: [
                Text(
                  '${_readerTopics.length} illustrated ${subject.name} topics — '
                  'full diagrams, tables and worked definitions, in one reader.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _openReader(null),
                  icon: const Icon(Icons.auto_stories_rounded, size: 17),
                  label: const Text('Open the illustrated notes'),
                ),
              ],
            ),
          ),
        ],
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
    this.hasReader = false,
    this.opensReader = false,
  });

  final NoteTopic topic;
  final Color accent;
  final VoidCallback onTap;

  /// This topic also exists as a fully illustrated note in the reader.
  final bool hasReader;

  /// Tapping goes straight to the reader, because there is no Firestore note.
  final bool opensReader;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Opacity(
        // A topic with no note yet is dimmed but still tappable — it leads to the
        // "coming soon" note and the option to practise it anyway.
        opacity: topic.hasNote || hasReader ? 1 : 0.6,
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
              if (hasReader) ...[
                const AppBadge(
                  label: 'Diagrams',
                  tone: BadgeTone.gold,
                  icon: Icons.auto_awesome_mosaic_rounded,
                ),
                const SizedBox(width: Tokens.s2),
              ] else if (!topic.hasNote) ...[
                const AppBadge(label: 'Coming soon'),
                const SizedBox(width: Tokens.s2),
              ],
              Icon(
                opensReader
                    ? Icons.open_in_new_rounded
                    : Icons.chevron_right_rounded,
                size: opensReader ? 15 : 18,
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
    required this.onOpenReader,
    this.reader,
  });

  final Subject subject;
  final NoteTopic topic;
  final VoidCallback onBack;
  final VoidCallback onTakeTest;

  /// The illustrated version of this topic, when one is published.
  final ReaderTopic? reader;
  final void Function(ReaderTopic?) onOpenReader;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // A note uploaded as a whole HTML file is a page, not a paragraph: it lays
    // itself out, and it is long. It gets the screen and scrolls itself, with
    // the test CTA parked below it — a page-height document nested inside this
    // ListView would mean two scrolls fighting over one drag.
    if (topic.hasNote && isNoteDocument(topic.note!.content)) {
      return _documentReader(context);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
      children: [
        _BackLink(label: subject.name, onTap: onBack),
        PageHeader(title: topic.topic, subtitle: subject.name),
        AppCard(
          child: topic.hasNote
              // The admin writes raw HTML, so a note carries the teacher's own
              // colours, highlights, tables and diagrams. NoteHtml renders that
              // faithfully and safely — see its doc comment.
              ? NoteHtml(html: topic.note!.content)
              : const EmptyState(
                  icon: Icons.hourglass_empty_rounded,
                  title: 'Notes coming soon',
                  message: "Your teachers haven't written notes for this topic "
                      'yet — check back later.',
                ),
        ),
        if (reader != null) ...[
          const SizedBox(height: Tokens.s4),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s4,
              vertical: Tokens.s5,
            ),
            child: Column(
              children: [
                Text(
                  'This topic also has an illustrated version, with diagrams '
                  'the note above cannot show.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => onOpenReader(reader),
                  icon: const Icon(Icons.auto_awesome_mosaic_rounded, size: 17),
                  label: const Text('Open the illustrated note'),
                ),
              ],
            ),
          ),
        ],
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

  /// The reader for a note that is a whole HTML document.
  ///
  /// The note fills the screen because that is what it was written to do: a
  /// Biology topic runs to several pages of headings, tables and labelled
  /// diagrams, and a phone shows it the way the browser would rather than as a
  /// tall card inside a scrolling list.
  ///
  /// What is left around it is only what the student cannot get from the page
  /// itself — the way back, and the test on this topic.
  Widget _documentReader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BackLink(label: subject.name, onTap: onBack),
              PageHeader(title: topic.topic, subtitle: subject.name),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.rSm),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Tokens.rSm),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? BlueprintPalette.b200.withValues(alpha: 0.25)
                        : BlueprintPalette.b100,
                  ),
                ),
                child: NoteDocumentView(html: topic.note!.content),
              ),
            ),
          ),
        ),
        // Pinned rather than scrolled past: a student who has read to the bottom
        // of a six-page note should not have to scroll a second surface to find
        // the test, and one who hasn't should still see it is there.
        Material(
          color: scheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.s4,
                Tokens.s3,
                Tokens.s4,
                Tokens.s3,
              ),
              child: Row(
                children: [
                  if (reader != null) ...[
                    OutlinedButton.icon(
                      onPressed: () => onOpenReader(reader),
                      icon: const Icon(Icons.auto_awesome_mosaic_rounded, size: 16),
                      label: const Text('Illustrated'),
                    ),
                    const SizedBox(width: Tokens.s2),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onTakeTest,
                      icon: const Icon(Icons.edit_rounded, size: 17),
                      label: const Text('Take a Test on This Topic'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
