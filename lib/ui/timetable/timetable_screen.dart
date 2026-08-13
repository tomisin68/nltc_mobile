import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/study_plan_repository.dart';
import '../../domain/models/subject.dart';
import '../../domain/study_plan.dart';
import '../core/state/dashboard_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/skeleton.dart';

/// The weekly study timetable.
///
/// A student picks four to seven subjects once. Every Monday the week is laid
/// out again from those subjects — one topic a day, each opening its study note,
/// and no topic coming round twice until the whole subject has been covered.
///
/// The rules deciding what lands on which day live in `domain/study_plan.dart`,
/// not here: the website runs the identical algorithm and the two must agree.
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  Map<String, List<PlanTopic>>? _syllabus;
  StudyPlan? _plan;
  bool _loading = true;
  bool _saving = false;

  /// Open when the student has no plan yet, or asked to change their subjects.
  bool _picking = false;

  /// The picker's working selection. Seeded from the saved plan when the student
  /// reopens it, and left empty for someone choosing for the first time.
  Set<String> _draft = {};

  SubjectCategory get _category =>
      (context.read<SessionController>().profile?.isJunior ?? false)
          ? SubjectCategory.junior
          : SubjectCategory.senior;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<StudyPlanRepository>();
    final uid = context.read<SessionController>().account?.uid ?? '';
    final category = _category.wireName;

    Map<String, List<PlanTopic>> syllabus;
    try {
      syllabus = await repo.syllabus(category);
    } catch (_) {
      syllabus = const {};
    }
    final plan = await repo.mine(uid);
    if (!mounted) return;

    setState(() {
      _syllabus = syllabus;
      _plan = plan;
      _loading = false;
      _draft = plan.subjects.toSet();
    });

    await _regenerateIfStale();
  }

  /// The Monday rebuild.
  ///
  /// Whichever surface the student opens first that week rebuilds the plan and
  /// writes it; the other reads it back. Because [buildWeek] is a pure function
  /// of the same inputs on both, it does not matter which one gets there first.
  Future<void> _regenerateIfStale() async {
    final plan = _plan;
    final syllabus = _syllabus;
    if (plan == null || syllabus == null || !plan.hasSubjects) return;

    final week = weekKey();
    if (!plan.isStale(week)) return;

    await _persist(plan.copyWith(
      weekOf: week,
      slots: buildWeek(
        subjects: plan.subjects,
        topicsBySubject: syllabus,
        covered: plan.covered,
        weekStartKey: week,
      ),
    ));
  }

  Future<void> _persist(StudyPlan next) async {
    if (!mounted) return;
    final uid = context.read<SessionController>().account?.uid ?? '';
    if (uid.isEmpty) return;
    setState(() => _plan = next);
    try {
      await context
          .read<StudyPlanRepository>()
          .save(uid, next, category: _category.wireName);
    } catch (_) {
      if (mounted) {
        showToast('Could not save your timetable', variant: ToastVariant.error);
      }
    }
  }

  Future<void> _confirmSelection() async {
    final problem = validateSelection(_draft.toList());
    if (problem != null) {
      showToast(problem, variant: ToastVariant.error);
      return;
    }

    setState(() => _saving = true);
    final week = weekKey();
    final subjects = _draft.toList()..sort();
    final covered = _plan?.covered ?? <String>{};

    await _persist(StudyPlan(
      subjects: subjects,
      weekOf: week,
      slots: buildWeek(
        subjects: subjects,
        topicsBySubject: _syllabus ?? const {},
        // Coverage for a dropped subject is kept rather than wiped: a student
        // who drops Chemistry this term and takes it up again next term should
        // not be made to study its first twenty topics over.
        covered: covered,
        weekStartKey: week,
      ),
      covered: covered,
    ));

    if (!mounted) return;
    setState(() {
      _saving = false;
      _picking = false;
    });
    showToast('Timetable built from ${subjects.length} subjects');
  }

  Future<void> _toggleCovered(PlanSlot slot) async {
    final plan = _plan;
    if (plan == null || slot.subject == null || slot.topic == null) return;

    final key = coverKey(slot.subject!, slot.topic!);
    final covered = {...plan.covered};
    final wasDone = covered.contains(key);
    if (wasDone) {
      covered.remove(key);
    } else {
      covered.add(key);
    }

    /* Ticking a day off does not re-cut the week — the remaining days stay put,
       so a student never watches tomorrow change under them for finishing
       today. The new coverage is picked up by next Monday's build. */
    await _persist(plan.copyWith(covered: covered));
    if (!wasDone && mounted) showToast('Topic marked as studied');
  }

  /// Opens the study notes for a day's topic.
  ///
  /// Opening the note is the honest signal that the topic was studied, so the
  /// journey advances on the action rather than on a checkbox the student has to
  /// remember. The tick is still there to undo it.
  Future<void> _study(PlanSlot slot) async {
    final plan = _plan;
    if (plan == null || slot.subject == null || slot.topic == null) return;

    final key = coverKey(slot.subject!, slot.topic!);
    if (!plan.covered.contains(key)) {
      await _persist(plan.copyWith(covered: {...plan.covered, key}));
    }
    if (!mounted) return;
    context
        .read<DashboardController>()
        .openNote(subject: slot.subject!, topic: slot.topic!);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const header = PageHeader(
      title: 'Timetable',
      subtitle: 'Your week of study, built from your subjects — one topic a '
          'day, straight through the syllabus.',
    );

    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
        children: const [
          header,
          SkeletonListItem(lines: 2),
          SizedBox(height: Tokens.s3),
          SkeletonListItem(lines: 2),
          SizedBox(height: Tokens.s3),
          SkeletonListItem(lines: 2),
        ],
      );
    }

    final syllabus = _syllabus ?? const <String, List<PlanTopic>>{};
    // Only subjects with notes written for them can be scheduled — a subject
    // with nothing behind it would put empty days on the timetable.
    final available = syllabus.keys
        .where((s) => (syllabus[s] ?? const []).isNotEmpty)
        .toList()
      ..sort();

    if (available.length < minPlanSubjects) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
        children: [
          header,
          EmptyState(
            icon: Icons.menu_book_rounded,
            title: 'Not enough study notes yet',
            message: 'A timetable needs at least $minPlanSubjects subjects with '
                'notes written for them. '
                '${available.length == 1 ? 'One subject has' : '${available.length} subjects have'} '
                'notes so far — check back once your tutors have uploaded more.',
          ),
        ],
      );
    }

    final plan = _plan ?? StudyPlan.empty;
    if (!plan.hasSubjects || _picking) {
      return _SubjectPicker(
        header: header,
        available: available,
        syllabus: syllabus,
        draft: _draft,
        saving: _saving,
        returning: plan.hasSubjects,
        onToggle: (name) => setState(() {
          if (_draft.contains(name)) {
            _draft.remove(name);
          } else if (_draft.length < maxPlanSubjects) {
            _draft.add(name);
          } else {
            showToast('That is the most you can take — $maxPlanSubjects '
                'subjects, one for each day.');
          }
        }),
        onConfirm: _confirmSelection,
        onCancel: plan.hasSubjects
            ? () => setState(() {
                  _picking = false;
                  _draft = plan.subjects.toSet();
                })
            : null,
      );
    }

    final week = weekKey();
    final progress = planProgress(plan.subjects, syllabus, plan.covered);
    final todayIndex = DateTime.now().weekday - DateTime.monday;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
      children: [
        header,
        _WeekBar(
          week: week,
          onChangeSubjects: () => setState(() {
            _picking = true;
            _draft = plan.subjects.toSet();
          }),
        ),
        const SizedBox(height: Tokens.s4),
        if (progress.complete) ...[
          _DoneBanner(subjects: plan.subjects.length, topics: progress.total),
          const SizedBox(height: Tokens.s4),
        ],
        for (final slot in plan.slots)
          _DayBlock(
            slot: slot,
            date: dayOfWeekKey(week, slot.day),
            isToday: slot.day == todayIndex,
            done: slot.subject != null &&
                plan.covered.contains(coverKey(slot.subject!, slot.topic!)),
            onToggle: () => _toggleCovered(slot),
            onStudy: () => _study(slot),
          ),
        const SizedBox(height: Tokens.s4),
        _ProgressPanel(progress: progress),
      ],
    );
  }
}

// ─── Subject picker ──────────────────────────────────────────────────────────

class _SubjectPicker extends StatelessWidget {
  const _SubjectPicker({
    required this.header,
    required this.available,
    required this.syllabus,
    required this.draft,
    required this.saving,
    required this.returning,
    required this.onToggle,
    required this.onConfirm,
    required this.onCancel,
  });

  final Widget header;
  final List<String> available;
  final Map<String, List<PlanTopic>> syllabus;
  final Set<String> draft;
  final bool saving;
  final bool returning;
  final void Function(String) onToggle;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enough = draft.length >= minPlanSubjects && draft.length <= maxPlanSubjects;
    final atMax = draft.length >= maxPlanSubjects;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s4),
            children: [
              header,
              Text(
                returning ? 'Change your subjects' : 'Choose your subjects',
                style: GoogleFonts.fraunces(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pick between $minPlanSubjects and $maxPlanSubjects subjects and '
                'we will build your week around them — a topic a day, in order, '
                'with nothing repeated until you have been through the whole '
                'subject.${returning ? ' What you have already covered is kept.' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Tokens.s4),
              for (final name in available)
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.s2),
                  child: _PickRow(
                    name: name,
                    topicCount: (syllabus[name] ?? const []).length,
                    selected: draft.contains(name),
                    dimmed: !draft.contains(name) && atMax,
                    onTap: () => onToggle(name),
                  ),
                ),
            ],
          ),
        ),
        _PickerBar(
          count: draft.length,
          enough: enough,
          saving: saving,
          onConfirm: onConfirm,
          onCancel: onCancel,
        ),
      ],
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.name,
    required this.topicCount,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final String name;
  final int topicCount;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subject = Subjects.one(name);

    return Opacity(
      // Dimmed once seven are taken — still readable, clearly not takeable.
      opacity: dimmed ? 0.5 : 1,
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.rMd),
          child: Container(
            padding: const EdgeInsets.all(Tokens.s3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.rMd),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: subject.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Tokens.rSm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(subject.icon, size: 16, color: subject.color),
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        '$topicCount topics',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? scheme.primary : Colors.transparent,
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar pinned under the picker: how many are chosen, and the way forward.
class _PickerBar extends StatelessWidget {
  const _PickerBar({
    required this.count,
    required this.enough,
    required this.saving,
    required this.onConfirm,
    required this.onCancel,
  });

  final int count;
  final bool enough;
  final bool saving;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final short = minPlanSubjects - count;

    return Container(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s3, Tokens.s4, Tokens.s4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                short > 0
                    ? '$count of $maxPlanSubjects chosen — $short more to go'
                    : '$count of $maxPlanSubjects chosen',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: enough ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (onCancel != null) ...[
              TextButton(
                onPressed: saving ? null : onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: Tokens.s2),
            ],
            FilledButton(
              onPressed: enough && !saving ? onConfirm : null,
              child: Text(saving ? 'Building…' : 'Build my timetable'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── The week ────────────────────────────────────────────────────────────────

class _WeekBar extends StatelessWidget {
  const _WeekBar({required this.week, required this.onChangeSubjects});

  final String week;
  final VoidCallback onChangeSubjects;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final from = dayOfWeekKey(week, 0);
    final to = dayOfWeekKey(week, 6);
    final format = DateFormat('d MMM');

    return Container(
      padding: const EdgeInsets.all(Tokens.s3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This week',
                  style: GoogleFonts.fraunces(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  '${format.format(from)} – ${format.format(to)} · rebuilds every Monday',
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onChangeSubjects,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.tune_rounded, size: 15),
            label: const Text('Subjects', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _DoneBanner extends StatelessWidget {
  const _DoneBanner({required this.subjects, required this.topics});

  final int subjects;
  final int topics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Tokens.rMd),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events_rounded, size: 22, color: scheme.tertiary),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You have covered every topic in all $subjects subjects.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$topics topics, start to finish. Add a subject to keep going.',
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
    );
  }
}

/// One day of the week, with the topic it holds.
class _DayBlock extends StatelessWidget {
  const _DayBlock({
    required this.slot,
    required this.date,
    required this.isToday,
    required this.done,
    required this.onToggle,
    required this.onStudy,
  });

  final PlanSlot slot;
  final DateTime date;
  final bool isToday;
  final bool done;
  final VoidCallback onToggle;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: isToday
                      ? BlueprintPalette.b600
                      : (isDark
                          ? scheme.surfaceContainerHigh
                          : BlueprintPalette.b50),
                  borderRadius: BorderRadius.circular(Tokens.rXs),
                ),
                child: Column(
                  children: [
                    Text(
                      dayShort[slot.day].toUpperCase(),
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                        color: isToday
                            ? BlueprintPalette.white.withValues(alpha: 0.85)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${date.day}',
                      style: GoogleFonts.fraunces(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        color:
                            isToday ? BlueprintPalette.white : scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Tokens.s3),
              Text(
                dayNames[slot.day],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: Tokens.s2),
                Text(
                  'TODAY',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: scheme.primary,
                  ),
                ),
              ],
              const SizedBox(width: Tokens.s2),
              Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
            ],
          ),
          const SizedBox(height: Tokens.s2),
          Padding(
            padding: const EdgeInsets.only(left: 54),
            child: slot.rest
                ? Row(
                    children: [
                      Icon(Icons.local_cafe_rounded,
                          size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Nothing left to study — take the day.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  )
                : _SlotCard(
                    slot: slot,
                    done: done,
                    onToggle: onToggle,
                    onStudy: onStudy,
                  ),
          ),
        ],
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.done,
    required this.onToggle,
    required this.onStudy,
  });

  final PlanSlot slot;
  final bool done;
  final VoidCallback onToggle;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subject = Subjects.one(slot.subject ?? '');

    return Opacity(
      // Studied: it stays on the page — it is what the week held — but steps
      // back so the eye lands on what is still to do.
      opacity: done ? 0.62 : 1,
      child: Container(
        padding: const EdgeInsets.all(Tokens.s3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(Tokens.rSm),
          border: Border(
            left: BorderSide(color: subject.color, width: 3),
            top: BorderSide(color: scheme.outlineVariant),
            right: BorderSide(color: scheme.outlineVariant),
            bottom: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: done ? 'Mark as not studied' : 'Mark as studied',
                  button: true,
                  child: InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(100),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? scheme.primary : Colors.transparent,
                        border: Border.all(
                          color: done ? scheme.primary : scheme.outlineVariant,
                          width: 1.5,
                        ),
                      ),
                      child: done
                          ? Icon(Icons.check_rounded,
                              size: 15, color: scheme.onPrimary)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(subject.icon, size: 11, color: subject.color),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              (slot.subject ?? '').toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                color: subject.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        slot.topic ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                          color: scheme.onSurface,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.s3),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStudy,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                ),
                icon: const Icon(Icons.menu_book_rounded, size: 16),
                label: const Text('Study notes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Progress ────────────────────────────────────────────────────────────────

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.progress});

  final PlanProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Your progress',
                  style: GoogleFonts.fraunces(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Text(
                '${progress.done} of ${progress.total} topics',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          for (final p in progress.perSubject) _Bar(progress: p),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.progress});

  final SubjectProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subject = Subjects.one(progress.subject);
    final complete = progress.complete;

    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(subject.icon, size: 12, color: subject.color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  progress.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (complete)
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 12, color: scheme.tertiary),
                    const SizedBox(width: 3),
                    Text(
                      'Completed',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: scheme.tertiary,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  '${progress.done}/${progress.total}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(color: scheme.surfaceContainerHigh),
                  ),
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: progress.fraction.clamp(0.0, 1.0)),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: value,
                        child: ColoredBox(
                          color: complete ? scheme.tertiary : subject.color,
                        ),
                      ),
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
}
