import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/learning_profile_repository.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/subject_repository.dart';
import '../../../data/services/firestore_cache.dart';
import '../../../domain/models/exam_result.dart';
import '../../../domain/models/subject.dart';
import '../../core/theme/app_palette.dart';
import '../../practice/exam_setup_sheet.dart';
import '../../core/state/practice_controller.dart';
import 'desk_card.dart';

/// The tabbed progress card: score trend, syllabus coverage, and weak topics.
///
/// Port of `ProgressNotebook`. Each tab loads only when first opened — the
/// coverage tab in particular costs an aggregate query per subject, and a student
/// who never opens it should never pay for it.
class ProgressNotebook extends StatefulWidget {
  const ProgressNotebook({
    super.key,
    required this.uid,
    required this.results,
    required this.isJunior,
  });

  final String uid;

  /// Null while loading.
  final List<ExamResult>? results;
  final bool isJunior;

  @override
  State<ProgressNotebook> createState() => _ProgressNotebookState();
}

enum _NotebookTab { trend, coverage, focus }

class _ProgressNotebookState extends State<ProgressNotebook> {
  _NotebookTab _tab = _NotebookTab.trend;

  /// Tabs the student has actually opened, so their loads stay lazy.
  final Set<_NotebookTab> _visited = {_NotebookTab.trend};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DeskCard(
      number: '03',
      title: 'Progress Notebook',
      padding: const EdgeInsets.fromLTRB(
        Tokens.s4,
        Tokens.s3,
        Tokens.s4,
        Tokens.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The pill switcher — `.dh-tabs`.
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              children: [
                for (final tab in _NotebookTab.values)
                  Expanded(
                    child: _TabButton(
                      label: switch (tab) {
                        _NotebookTab.trend => 'Score trend',
                        _NotebookTab.coverage => 'Coverage',
                        _NotebookTab.focus => 'Focus areas',
                      },
                      active: _tab == tab,
                      onTap: () => setState(() {
                        _tab = tab;
                        _visited.add(tab);
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s4),
          // Kept mounted once visited, so switching back doesn't re-fetch.
          if (_visited.contains(_NotebookTab.trend))
            Offstage(
              offstage: _tab != _NotebookTab.trend,
              child: _TrendTab(results: widget.results),
            ),
          if (_visited.contains(_NotebookTab.coverage))
            Offstage(
              offstage: _tab != _NotebookTab.coverage,
              child: _CoverageTab(uid: widget.uid, isJunior: widget.isJunior),
            ),
          if (_visited.contains(_NotebookTab.focus))
            Offstage(
              offstage: _tab != _NotebookTab.focus,
              child: _FocusTab(uid: widget.uid),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: active ? scheme.surfaceContainerLowest : Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

// ─── Trend ──────────────────────────────────────────────────────────────────

class _TrendTab extends StatelessWidget {
  const _TrendTab({required this.results});

  final List<ExamResult>? results;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (results == null) return const DeskCardSpinner(height: 180);

    // Oldest to newest, last fifteen — the same window the web charts.
    final trend = results!.reversed.toList();
    final window = trend.length > 15 ? trend.sublist(trend.length - 15) : trend;

    if (window.isEmpty) {
      return const DeskCardEmpty(
        icon: Icons.show_chart_rounded,
        message: 'Your score trend will appear here after your first few '
            'practice sessions.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Score trend — last ${window.length} '
          'session${window.length == 1 ? '' : 's'}',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Tokens.s3),
        SizedBox(
          height: 170,
          // The width matters as much as the height. A `CustomPaint` with no
          // child sizes itself to `constraints.constrain(Size.zero)`, and the
          // column above hands out loose horizontal constraints, so without
          // this the painter is handed a zero-width canvas, bails out of
          // `paint`, and the card shows an empty gap where the line should be.
          width: double.infinity,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Motion.enter,
            builder: (context, reveal, _) => CustomPaint(
              painter: _TrendPainter(
                scores: [for (final r in window) r.percent.toDouble()],
                labels: [
                  for (final r in window)
                    r.submittedAt == null
                        ? ''
                        : DateFormat('d MMM').format(r.submittedAt!),
                ],
                line: scheme.primary,
                fill: scheme.primary.withValues(alpha: 0.14),
                grid: scheme.outlineVariant,
                text: scheme.onSurfaceVariant,
                reveal: reveal,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Draws the score line.
///
/// Hand-painted rather than pulling in a charting package: it is one series over
/// at most fifteen points with a fixed 0–100 axis, and a package would add weight
/// to every build for a single card.
class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.scores,
    required this.labels,
    required this.line,
    required this.fill,
    required this.grid,
    required this.text,
    required this.reveal,
  });

  final List<double> scores;
  final List<String> labels;
  final Color line;
  final Color fill;
  final Color grid;
  final Color text;

  /// 0..1 — how much of the line to draw, for the entry animation.
  final double reveal;

  static const _leftGutter = 30.0;
  static const _bottomGutter = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - _leftGutter;
    final plotHeight = size.height - _bottomGutter;
    if (plotWidth <= 0 || plotHeight <= 0 || scores.isEmpty) return;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    // 0, 25, 50, 75, 100 — the same ticks as the web's `stepSize: 25`.
    for (var value = 0; value <= 100; value += 25) {
      final y = plotHeight - (value / 100) * plotHeight;
      canvas.drawLine(Offset(_leftGutter, y), Offset(size.width, y), gridPaint);
      _label(canvas, '$value', Offset(0, y - 6), 9, text);
    }

    Offset pointAt(int i) {
      final x = scores.length == 1
          ? _leftGutter + plotWidth / 2
          : _leftGutter + (plotWidth * i / (scores.length - 1));
      final y = plotHeight - (scores[i].clamp(0, 100) / 100) * plotHeight;
      return Offset(x, y);
    }

    final visible = (scores.length * reveal).ceil().clamp(1, scores.length);
    final points = [for (var i = 0; i < visible; i++) pointAt(i)];

    // The area under the line, which is what makes a rising trend read as
    // progress rather than as a squiggle.
    if (points.length > 1) {
      final area = Path()..moveTo(points.first.dx, plotHeight);
      for (final p in points) {
        area.lineTo(p.dx, p.dy);
      }
      area
        ..lineTo(points.last.dx, plotHeight)
        ..close();
      canvas.drawPath(area, Paint()..color = fill);
    }

    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (points.length > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    final dot = Paint()..color = line;
    for (final p in points) {
      canvas.drawCircle(p, 3, dot);
    }

    // Only the ends are labelled: fifteen dates across a phone would collide.
    if (labels.isNotEmpty) {
      _label(canvas, labels.first, Offset(_leftGutter, plotHeight + 6), 9, text);
      if (labels.length > 1) {
        _label(
          canvas,
          labels.last,
          Offset(size.width - 42, plotHeight + 6),
          9,
          text,
        );
      }
    }
  }

  void _label(
    Canvas canvas,
    String value,
    Offset at,
    double fontSize,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: fontSize, color: color),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.reveal != reveal ||
      old.line != line ||
      !_sameScores(old.scores, scores);

  static bool _sameScores(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ─── Coverage ───────────────────────────────────────────────────────────────

/// How much of each subject's bank this student has already been served.
class _CoverageTab extends StatefulWidget {
  const _CoverageTab({required this.uid, required this.isJunior});

  final String uid;
  final bool isJunior;

  @override
  State<_CoverageTab> createState() => _CoverageTabState();
}

class _SubjectCoverage {
  const _SubjectCoverage({
    required this.name,
    required this.seen,
    required this.total,
  });

  final String name;
  final int seen;
  final int total;

  int get percent => total == 0 ? 0 : ((seen / total) * 100).round();
}

class _CoverageTabState extends State<_CoverageTab> {
  List<_SubjectCoverage>? _coverage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bank = widget.isJunior
        ? QuestionRepository.juniorBank
        : QuestionRepository.seniorBank;
    final subjects = context.read<SubjectRepository>();
    final learning = context.read<LearningProfileRepository>();
    final cache = context.read<FirestoreCache>();

    try {
      final names = await subjects.names(
        widget.isJunior ? SubjectCategory.junior : SubjectCategory.senior,
      );
      final profile = await learning.load(widget.uid);
      final seenIds = profile.seenQuestions.keys.toList();

      final rows = await cache.read<List<_SubjectCoverage>>(
        // Same cache key the web uses, so the two don't each pay for the count.
        'subjectCoverage_${widget.uid}_$bank',
        CacheTtl.userResults,
        () => _compute(bank, names, seenIds),
        // Deliberately memory-only: the shape is a list of records, and a wrong
        // decode on a cold start would be worse than paying for the read again.
      );

      if (mounted) setState(() => _coverage = rows);
    } catch (_) {
      if (mounted) setState(() => _coverage = const []);
    }
  }

  /// Resolves which subject each seen question belongs to, then counts the bank.
  Future<List<_SubjectCoverage>> _compute(
    String bank,
    List<String> names,
    List<String> seenIds,
  ) async {
    final db = FirebaseFirestore.instance;

    // Firestore caps `whereIn` at 30 ids, so the lookup is chunked.
    final seenBySubject = <String, int>{};
    for (var i = 0; i < seenIds.length; i += 30) {
      final chunk = seenIds.sublist(i, (i + 30).clamp(0, seenIds.length));
      try {
        final snap = await db
            .collection(bank)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final subject = (doc.data()['subject'] ?? '').toString();
          if (subject.isEmpty) continue;
          seenBySubject[subject] = (seenBySubject[subject] ?? 0) + 1;
        }
      } catch (_) {
        // A chunk that fails costs a little accuracy, not the whole card.
      }
    }

    final rows = <_SubjectCoverage>[];
    for (final name in names) {
      try {
        // `count()` is billed at a fraction of a document read, which is what
        // makes counting a whole bank affordable at all.
        final count = await db
            .collection(bank)
            .where('subject', isEqualTo: name)
            .count()
            .get();
        final total = count.count ?? 0;
        if (total == 0) continue;
        rows.add(
          _SubjectCoverage(
            name: name,
            seen: (seenBySubject[name] ?? 0).clamp(0, total),
            total: total,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverage = _coverage;
    if (coverage == null) return const DeskCardSpinner(height: 120);
    if (coverage.isEmpty) {
      return const DeskCardEmpty(
        icon: Icons.layers_rounded,
        message: "Practise some questions and we'll show how much of each "
            "subject's bank you've covered.",
      );
    }

    return Column(
      children: [
        for (final row in coverage)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    row.name,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: row.percent / 100,
                      minHeight: 7,
                      backgroundColor: scheme.surfaceContainerHigh,
                    ),
                  ),
                ),
                const SizedBox(width: Tokens.s2),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${row.percent}%',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.fraunces(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Focus areas ────────────────────────────────────────────────────────────

/// The weak topics the engine has spotted, each a shortcut into practice on it.
class _FocusTab extends StatefulWidget {
  const _FocusTab({required this.uid});

  final String uid;

  @override
  State<_FocusTab> createState() => _FocusTabState();
}

class _FocusTabState extends State<_FocusTab> {
  List<WeakTopic>? _topics;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile =
        await context.read<LearningProfileRepository>().load(widget.uid);
    if (mounted) setState(() => _topics = profile.weakTopics);
  }

  /// Opens the setup sheet already pointed at this topic — the app's equivalent of
  /// the web's `/cbt?mode=topic&topics=…&autostart=1`.
  Future<void> _practise(WeakTopic topic) async {
    final practice = context.read<PracticeController>();
    final entry = practice.entryFor(topic.subjectLabel);
    await showExamSetupSheet(context, entry, initialTopic: topic.topic);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topics = _topics;
    if (topics == null) return const DeskCardSpinner(height: 120);
    if (topics.isEmpty) {
      return const DeskCardEmpty(
        icon: Icons.adjust_rounded,
        message: 'Keep practising — the smart engine will spot your weak topics '
            'and list them here.',
      );
    }

    return Wrap(
      spacing: Tokens.s2,
      runSpacing: Tokens.s2,
      children: [
        for (final topic in topics)
          Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(Tokens.rMd),
            child: InkWell(
              onTap: () => _practise(topic),
              borderRadius: BorderRadius.circular(Tokens.rMd),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.s3,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Tokens.rMd),
                  border: Border.all(color: scheme.outlineVariant, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.subjectLabel,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      topic.topic,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${(topic.mastery * 100).round()}% mastery — tap to practise',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.error,
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
