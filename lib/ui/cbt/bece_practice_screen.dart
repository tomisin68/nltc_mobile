import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/exam_result_repository.dart';
import '../../data/repositories/subject_repository.dart';
import '../../domain/models/exam_config.dart';
import '../../domain/models/exam_result.dart';
import '../../domain/models/question.dart';
import '../../domain/models/subject.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/skeleton.dart';
import '../exam/exam_screen.dart';
import 'widgets/history_list.dart';
import 'widgets/mode_card.dart';

/// The three ways a junior student can practise.
enum BeceMode {
  exam('Exam Mode', Icons.school_rounded, 'Timed · past questions'),
  study('Study Mode', Icons.menu_book_rounded, 'Instant answers & explanations'),
  topic('Topic', Icons.place_rounded, 'Practice by specific topics');

  const BeceMode(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;
}

/// BECE Practice — the junior track.
///
/// Port of `src/pages/dashboard/BECEPracticeView.jsx`. Questions come from the
/// separate `jssQuestions` collection, not the senior bank, which is why this is
/// its own screen rather than a flag on CBT Practice.
class BecePracticeScreen extends StatefulWidget {
  const BecePracticeScreen({super.key});

  @override
  State<BecePracticeScreen> createState() => _BecePracticeScreenState();
}

class _BecePracticeScreenState extends State<BecePracticeScreen> {
  static const _bank = 'jssQuestions';
  static const _countOptions = [10, 20, 30, 40, 50];

  /// Minutes, or null for no timer.
  static const _timeOptions = <int?>[null, 15, 30, 45, 60];

  BeceMode _mode = BeceMode.exam;
  Subject? _subject;
  int _count = 30;
  int? _timeLimit;

  List<Subject> _subjects = const [];

  /// Subject keys the bank actually has questions for — the "Available" tick.
  final Set<String> _available = {};

  List<String> _topics = const [];
  final Set<String> _selectedTopics = {};
  bool _loadingTopics = false;

  List<ExamResult> _history = const [];
  bool _loadingHistory = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final subjectRepository = context.read<SubjectRepository>();
    final resultRepository = context.read<ExamResultRepository>();
    final uid = context.read<SessionController>().account?.uid;

    final subjects = await subjectRepository.decorated(SubjectCategory.junior);
    if (!mounted) return;
    setState(() => _subjects = subjects);
    _checkAvailability(subjects);

    if (uid == null) {
      setState(() => _loadingHistory = false);
      return;
    }
    final history = await resultRepository.recent(uid, limit: 100);
    if (!mounted) return;
    setState(() {
      // The web filters its own history down to BECE sittings; same here, since
      // a junior account can still hold senior results after an upgrade.
      _history = history.where((r) => r.exam == 'bece').toList();
      _loadingHistory = false;
    });
  }

  /// One cheap read per subject to see whether the bank has anything at all.
  Future<void> _checkAvailability(List<Subject> subjects) async {
    final db = FirebaseFirestore.instance;
    for (final subject in subjects) {
      try {
        final snap = await db
            .collection(_bank)
            .where('subject', isEqualTo: subject.name)
            .limit(1)
            .get();
        if (!mounted) return;
        if (snap.docs.isNotEmpty) setState(() => _available.add(subject.key));
      } catch (_) {
        // A subject we can't check simply shows no tick.
      }
    }
  }

  Future<void> _selectSubject(Subject subject) async {
    setState(() {
      _subject = subject;
      _topics = const [];
      _selectedTopics.clear();
      _loadingTopics = true;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection(_bank)
          .where('subject', isEqualTo: subject.name)
          .limit(2000)
          .get();
      final topics = <String>{};
      for (final doc in snap.docs) {
        final topic = doc.data()['topic'];
        if (topic is String && topic.trim().isNotEmpty) topics.add(topic.trim());
      }
      if (!mounted) return;
      setState(() {
        _topics = topics.toList()..sort();
        _loadingTopics = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _topics = const [];
        _loadingTopics = false;
      });
    }
  }

  Future<void> _start() async {
    final subject = _subject;
    if (subject == null || _starting) return;

    if (_mode == BeceMode.topic && _selectedTopics.isEmpty) {
      showToast('Please select at least one topic.', variant: ToastVariant.error);
      return;
    }

    // Captured before the draw: the sitting that follows is a route away, and
    // reaching back into the tree after it returns is what the
    // `use_build_context_synchronously` lint is about.
    final resultRepository = context.read<ExamResultRepository>();
    final uid = context.read<SessionController>().account?.uid;

    setState(() => _starting = true);
    final questions = await _drawQuestions(subject);
    if (!mounted) return;
    setState(() => _starting = false);

    if (questions.isEmpty) {
      showToast(
        'No questions found for ${subject.name} yet. Tell your tutor.',
        variant: ToastVariant.error,
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExamScreen(
          config: ExamConfig(
            subject: subject.name,
            exam: 'bece',
            topic: _selectedTopics.length == 1 ? _selectedTopics.first : null,
            questionCount: questions.length,
            mode: _mode == BeceMode.study ? ExamMode.practice : ExamMode.exam,
            duration:
                _timeLimit == null ? null : Duration(minutes: _timeLimit!),
          ),
          questions: questions,
        ),
      ),
    );

    // A finished sitting belongs in the history below, so drop the cached copy.
    if (uid != null && mounted) {
      resultRepository.invalidate(uid);
      await _load();
    }
  }

  /// Draws from `jssQuestions`, honouring the topic filter when there is one.
  Future<List<Question>> _drawQuestions(Subject subject) async {
    final db = FirebaseFirestore.instance;
    try {
      // Firestore cannot order randomly, so over-fetch and shuffle here — taking
      // the first N would serve the same paper every time.
      var query = db
          .collection(_bank)
          .where('subject', isEqualTo: subject.name)
          .limit(2000);

      // `whereIn` caps at 30 values; beyond that the filter is applied on the
      // client instead, which is fine since the whole subject is already read.
      final topics = _selectedTopics.toList();
      if (_mode == BeceMode.topic && topics.isNotEmpty && topics.length <= 30) {
        query = db
            .collection(_bank)
            .where('subject', isEqualTo: subject.name)
            .where('topic', whereIn: topics)
            .limit(2000);
      }

      final snap = await query.get();
      var pool = snap.docs
          .map((d) => Question.fromMap(d.id, d.data()))
          .where((q) => q.isUsable)
          .toList();

      if (_mode == BeceMode.topic && topics.length > 30) {
        pool = pool.where((q) => topics.contains(q.topic)).toList();
      }

      pool.shuffle();
      return pool.take(_count).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subject = _subject;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
      children: [
        const PageHeader(
          title: 'BECE Practice',
          subtitle: 'Junior Secondary School — practice BECE past questions by '
              'subject and topic.',
        ),

        // ── Mode ──
        AppCard(
          title: 'Practice Mode',
          titleIcon: Icons.settings_rounded,
          child: ModeGrid(
            children: [
              for (final mode in BeceMode.values)
                ModeCard(
                  icon: mode.icon,
                  name: mode.label,
                  description: mode.description,
                  selected: _mode == mode,
                  onTap: () => setState(() => _mode = mode),
                ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s4),

        // ── Subject ──
        AppCard(
          title: 'Select Subject',
          titleIcon: Icons.book_rounded,
          child: _subjects.isEmpty
              ? const SkeletonListItem(lines: 2)
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 132,
                    mainAxisSpacing: Tokens.s2,
                    crossAxisSpacing: Tokens.s2,
                    childAspectRatio: 0.92,
                  ),
                  itemCount: _subjects.length,
                  itemBuilder: (context, i) => _SubjectTile(
                    subject: _subjects[i],
                    selected: _subject?.key == _subjects[i].key,
                    available: _available.contains(_subjects[i].key),
                    onTap: () => _selectSubject(_subjects[i]),
                  ),
                ),
        ),
        const SizedBox(height: Tokens.s4),

        // ── Options ──
        if (subject == null)
          const AppCard(
            child: EmptyState(
              icon: Icons.touch_app_rounded,
              title: 'Select a subject above',
              message: 'Choose a subject to configure your practice session.',
            ),
          )
        else
          AppCard(
            title: '${subject.name} — ${_mode.label} Options',
            titleIcon: subject.icon,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_mode == BeceMode.topic) ...[
                  _TopicPicker(
                    topics: _topics,
                    selected: _selectedTopics,
                    loading: _loadingTopics,
                    count: _count,
                    onToggle: (topic) => setState(() {
                      if (!_selectedTopics.remove(topic)) {
                        _selectedTopics.add(topic);
                      }
                    }),
                    onSelectAll: () => setState(() {
                      if (_selectedTopics.length == _topics.length) {
                        _selectedTopics.clear();
                      } else {
                        _selectedTopics
                          ..clear()
                          ..addAll(_topics);
                      }
                    }),
                  ),
                  const SizedBox(height: Tokens.s4),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        label: 'Questions',
                        child: DropdownButtonFormField<int>(
                          initialValue: _count,
                          isDense: true,
                          items: [
                            for (final n in _countOptions)
                              DropdownMenuItem(
                                value: n,
                                child: Text('$n questions'),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _count = value ?? _count),
                        ),
                      ),
                    ),
                    if (_mode != BeceMode.study) ...[
                      const SizedBox(width: Tokens.s3),
                      Expanded(
                        child: _Field(
                          label: 'Time Limit',
                          child: DropdownButtonFormField<int?>(
                            initialValue: _timeLimit,
                            isDense: true,
                            items: [
                              for (final minutes in _timeOptions)
                                DropdownMenuItem(
                                  value: minutes,
                                  child: Text(
                                    minutes == null
                                        ? 'No timer'
                                        : '$minutes min',
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _timeLimit = value),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Tokens.s4),
                FilledButton.icon(
                  onPressed: _starting ? null : _start,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _starting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _mode == BeceMode.study
                              ? Icons.menu_book_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                        ),
                  label: Text(
                    switch (_mode) {
                      BeceMode.study => 'Start Study Session',
                      BeceMode.topic => 'Start Topic Practice',
                      BeceMode.exam => 'Start BECE Exam',
                    },
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: Tokens.s4),

        // ── History ──
        AppCard(
          title: 'Practice History',
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
              ? const SkeletonTable(rows: 4)
              : _history.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: Tokens.s5),
                      child: EmptyState(
                        icon: Icons.assignment_outlined,
                        title: 'No sessions yet',
                        message: 'Start your first BECE practice session above!',
                      ),
                    )
                  : HistoryList(results: _history, showType: false),
        ),
      ],
    );
  }
}

class _SubjectTile extends StatelessWidget {
  const _SubjectTile({
    required this.subject,
    required this.selected,
    required this.available,
    required this.onTap,
  });

  final Subject subject;
  final bool selected;
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Tokens.rMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.rMd),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: Tokens.s3,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(subject.icon, size: 21, color: subject.color),
              const SizedBox(height: 5),
              Text(
                subject.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: scheme.onSurface,
                ),
              ),
              if (available) ...[
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 9,
                      color: scheme.tertiary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'Available',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: scheme.tertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Multi-select topic picker.
///
/// The web uses a fixed-position dropdown panel with its own search. On a phone
/// the same choice is a full-height sheet, which is why the trigger opens one
/// rather than an inline popover.
class _TopicPicker extends StatelessWidget {
  const _TopicPicker({
    required this.topics,
    required this.selected,
    required this.loading,
    required this.count,
    required this.onToggle,
    required this.onSelectAll,
  });

  final List<String> topics;
  final Set<String> selected;
  final bool loading;
  final int count;
  final ValueChanged<String> onToggle;
  final VoidCallback onSelectAll;

  String get _summary {
    if (selected.isEmpty) return 'All topics — no filter';
    if (selected.length == topics.length) return 'All topics selected';
    if (selected.length == 1) return selected.first;
    return '${selected.length} of ${topics.length} topics selected';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (loading) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: Tokens.s2),
          Text(
            'Loading topics…',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    if (topics.isEmpty) {
      return Text(
        'No topics found — all available questions will be used.',
        style: TextStyle(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'TOPICS',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              '${selected.length}/${topics.length} selected',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onSelectAll,
              child: Text(
                selected.length == topics.length ? 'Deselect all' : 'Select all',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: () => _openSheet(context),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: selected.isEmpty
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$count questions will be drawn from ${selected.length} '
                  'topic${selected.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _openSheet(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _TopicSheet(
          topics: topics,
          selected: selected,
          onToggle: onToggle,
        ),
      );
}

class _TopicSheet extends StatefulWidget {
  const _TopicSheet({
    required this.topics,
    required this.selected,
    required this.onToggle,
  });

  final List<String> topics;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  State<_TopicSheet> createState() => _TopicSheetState();
}

class _TopicSheetState extends State<_TopicSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needle = _search.toLowerCase();
    final filtered = widget.topics
        .where((t) => needle.isEmpty || t.toLowerCase().contains(needle))
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s2, Tokens.s4, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                hintText: 'Search topics…',
                isDense: true,
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: Tokens.s2),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(Tokens.s5),
                      child: Text(
                        'No topics match "$_search"',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final topic = filtered[i];
                        return CheckboxListTile(
                          value: widget.selected.contains(topic),
                          onChanged: (_) {
                            widget.onToggle(topic);
                            // The set lives in the parent; rebuild this sheet so
                            // the tick appears immediately.
                            setState(() {});
                          },
                          title: Text(
                            topic,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Done (${widget.selected.length} selected)'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      );
}
