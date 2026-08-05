import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/attempt_repository.dart';
import '../../data/repositories/learning_profile_repository.dart';
import '../../domain/models/exam_config.dart';
import '../../domain/models/question.dart';
import '../../domain/models/subject.dart';
import '../core/anti_cheat.dart';
import '../core/state/exam_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/anti_cheat_warning.dart';
import '../core/widgets/calculator.dart';
import '../core/widgets/question_body.dart';
import 'exam_result_screen.dart';
import 'question_palette.dart';
import 'widgets/option_tile.dart';
import 'widgets/report_question_sheet.dart';

/// The CBT runner.
///
/// Owns nothing itself — [ExamController] holds the clock and the answer sheet
/// — so a rebuild from a theme change or a keyboard can never lose an answer.
class ExamScreen extends StatelessWidget {
  const ExamScreen({
    super.key,
    required this.config,
    required this.questions,
    this.submitter,
    this.onSubmitted,
  });

  final ExamConfig config;
  final List<Question> questions;

  /// Replaces the default submission — see [ExamController.submitter]. Used by
  /// mock exams, which are recorded against their own document.
  final Future<SubmitResult> Function(
    List<Question> questions,
    Map<String, String> answers,
    int durationSeconds,
  )? submitter;

  /// Replaces the jump to the results screen once the sitting is submitted.
  ///
  /// A mock exam has no score to show yet, so it lands on a pending screen
  /// instead. When null, the graded result screen is pushed as usual.
  final void Function(BuildContext context, ExamController controller)?
      onSubmitted;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (context) => ExamController(
          config: config,
          questions: questions,
          attempts: context.read<AttemptRepository>(),
          submitter: submitter,
        ),
        child: _ExamView(onSubmitted: onSubmitted),
      );
}

class _ExamView extends StatefulWidget {
  const _ExamView({this.onSubmitted});

  final void Function(BuildContext context, ExamController controller)?
      onSubmitted;

  @override
  State<_ExamView> createState() => _ExamViewState();
}

class _ExamViewState extends State<_ExamView>
    with WidgetsBindingObserver, AntiCheatObserver {
  final _pageController = PageController();
  ExamController? _controller;
  bool _navigated = false;

  /// The floating calculator, which stays put while the student pages between
  /// questions — closing it on every swipe would make it useless for the
  /// multi-step working a maths question actually needs.
  bool _calculatorOpen = false;

  /// Set while the anti-cheat overlay is up.
  bool _warningOpen = false;

  /// The page an animation is already heading for. Without this the timer's
  /// once-a-second rebuild would restart the scroll animation mid-flight and
  /// make the transition stutter.
  int? _animatingTo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<ExamController>();
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_onControllerChanged);
    _controller = controller..addListener(_onControllerChanged);

    // Only a real sitting is policed. Practice mode reveals the answers as you
    // go, so there is nothing to cheat at, and warning a student for checking a
    // notification during revision would be absurd.
    if (controller.config.mode == ExamMode.exam) startAntiCheat();
  }

  /// Tells the learning engine what was answered, and how.
  ///
  /// This is the other half of adaptive selection: without it the seen-question
  /// map never grows and the next sitting draws from the same pool as this one.
  /// Fire-and-forget by design — the sitting is already graded and saved, and a
  /// student on a bad connection must not be shown an error for it.
  void _recordForLearningEngine(ExamController controller) {
    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return;

    final records = <AnswerRecord>[];
    for (var i = 0; i < controller.total; i++) {
      final question = controller.questions[i];
      final chosen = controller.answerFor(question);
      records.add(
        AnswerRecord(
          questionId: question.id,
          // The engine keys ability by subject slug, so the section's key is
          // what goes on the wire — not the display name.
          subject: controller.sectionAt(i).key,
          topic: question.topic,
          difficultyLabel: question.difficulty,
          correct: question.isCorrect(chosen),
        ),
      );
    }

    context.read<LearningProfileRepository>().recordAnswers(uid, records);
  }

  // ─── Anti-cheat ────────────────────────────────────────────────────────────

  @override
  void onAntiCheatViolation(int count) {
    if (!mounted) return;
    setState(() => _warningOpen = true);
  }

  @override
  void onAntiCheatAutoSubmit() {
    if (!mounted) return;
    setState(() => _warningOpen = true);
    // The same beat the web waits before submitting, so the student reads why
    // their exam ended rather than finding themselves on a results screen.
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() => _warningOpen = false);
      _controller?.submit();
    });
  }

  /// Both the Submit button and the timer running out finish the sitting, so
  /// the navigation lives here — one exit, whichever door it came through.
  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || _navigated) return;

    if (controller.result != null) {
      _navigated = true;
      stopAntiCheat();
      _recordForLearningEngine(controller);
      final onSubmitted = widget.onSubmitted;
      if (onSubmitted != null) {
        onSubmitted(context, controller);
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ExamResultScreen(
            config: controller.config,
            questions: controller.questions,
            answers: {
              for (final q in controller.questions)
                if (controller.answerFor(q) != null) q.id: controller.answerFor(q)!,
            },
            result: controller.result!,
          ),
        ),
      );
      return;
    }

    if (!_pageController.hasClients) return;
    if (_pageController.page?.round() == controller.index) {
      _animatingTo = null;
      return;
    }
    if (_animatingTo == controller.index) return;

    _animatingTo = controller.index;
    _pageController
        .animateToPage(
          controller.index,
          duration: Motion.base,
          curve: Motion.emphasized,
        )
        .whenComplete(() => _animatingTo = null);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _confirmExit() async {
    final controller = context.read<ExamController>();
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this exam?'),
        content: Text(
          controller.answeredCount == 0
              ? 'Nothing has been answered yet, so nothing will be saved.'
              : 'You have answered ${controller.answeredCount} of '
                  '${controller.total}. Leaving now discards this sitting — it '
                  'will not be scored or saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if ((leave ?? false) && mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmSubmit() async {
    final controller = context.read<ExamController>();
    final unanswered = controller.unansweredCount;

    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit your answers?'),
        content: Text(
          unanswered == 0
              ? 'All ${controller.total} questions are answered. '
                  'Ready to see your score?'
              : '$unanswered question${unanswered == 1 ? '' : 's'} '
                  '${unanswered == 1 ? 'is' : 'are'} still unanswered. '
                  'Unanswered questions are marked wrong.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(unanswered == 0 ? 'Not yet' : 'Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (submit ?? false) await controller.submit();
  }

  Future<void> _openPalette() async {
    final controller = context.read<ExamController>();
    final target = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuestionPalette(controller: controller),
    );
    if (target != null) controller.goTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExamController>();
    final scheme = Theme.of(context).colorScheme;
    final section = controller.currentSection;

    return PopScope(
      // An accidental back swipe mid-exam would be unforgivable; the dialog
      // is the only way out.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Leave exam',
            onPressed: _confirmExit,
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Numbering is per subject in a multi-subject paper — "Q12 of
                // 40" of English, not "Q12 of 180" of the whole morning.
                'Question ${section.numberAt(controller.index)} of '
                '${section.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                section.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            if (controller.config.isTimed) _TimerPill(controller: controller),
            IconButton(
              onPressed: () =>
                  setState(() => _calculatorOpen = !_calculatorOpen),
              icon: Icon(
                Icons.calculate_rounded,
                color: _calculatorOpen ? scheme.primary : null,
              ),
              tooltip: _calculatorOpen ? 'Hide calculator' : 'Calculator',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(
              controller.config.isMultiSubject ? 47 : 3,
            ),
            child: Column(
              children: [
                if (controller.config.isMultiSubject)
                  _SubjectPills(controller: controller),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: controller.progress),
                  duration: Motion.base,
                  curve: Motion.enter,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: controller.total,
                onPageChanged: controller.goTo,
                itemBuilder: (context, i) => _QuestionPage(
                  controller: controller,
                  question: controller.questions[i],
                ),
              ),
              if (_calculatorOpen)
                Positioned(
                  right: Tokens.s3,
                  bottom: Tokens.s3,
                  child: _FloatingCalculator(
                    onClose: () => setState(() => _calculatorOpen = false),
                  ),
                ),
              if (_warningOpen)
                AntiCheatWarning(
                  violations: antiCheatViolations,
                  maxViolations: antiCheatMaxViolations,
                  isFinal: antiCheatAutoSubmitted,
                  onDismiss: () => setState(() => _warningOpen = false),
                ),
            ],
          ),
        ),
        bottomNavigationBar: _ExamToolbar(
          controller: controller,
          onPalette: _openPalette,
          onSubmit: _confirmSubmit,
        ),
      ),
    );
  }
}

// ─── Subject pills ──────────────────────────────────────────────────────────

/// The subject strip across the top of a multi-subject paper.
///
/// Port of `.exam-subject-pills`: each subject shows how many of its questions
/// are answered, and tapping one jumps to its first question — which is how a
/// candidate moves between papers in the real hall.
class _SubjectPills extends StatelessWidget {
  const _SubjectPills({required this.controller});

  final ExamController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sections = controller.sections;
    final currentIndex = controller.currentSectionIndex;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(width: Tokens.s2),
        itemBuilder: (context, i) {
          final section = sections[i];
          final active = i == currentIndex;
          final decoration = Subjects.decorate([section.name]).first;
          final answered = controller.answeredIn(section);

          return Center(
            child: Material(
              color: active
                  ? decoration.color.withValues(alpha: 0.16)
                  : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(100),
              child: InkWell(
                onTap: () => controller.goToSection(section),
                borderRadius: BorderRadius.circular(100),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s3,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: active ? decoration.color : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(decoration.icon, size: 13, color: decoration.color),
                      const SizedBox(width: 5),
                      Text(
                        // First word only, as the web does — "Further" reads
                        // fine in a pill where "Further Mathematics" would not.
                        section.name.split(' ').first,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          '$answered/${section.length}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: answered == section.length
                                ? BlueprintPalette.success
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Floating calculator ────────────────────────────────────────────────────

/// The calculator, docked over the paper rather than in a sheet.
///
/// A sheet would cover the question, which defeats the point — the working a
/// student is doing belongs to the numbers they can still see. The web floats it
/// for the same reason.
class _FloatingCalculator extends StatelessWidget {
  const _FloatingCalculator({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(Tokens.rMd),
      shadowColor: scheme.shadow.withValues(alpha: 0.4),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 280,
          maxHeight: MediaQuery.sizeOf(context).height * 0.62,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Tokens.rMd),
          child: Calculator(onClose: onClose),
        ),
      ),
    );
  }
}

// ─── Timer ──────────────────────────────────────────────────────────────────

class _TimerPill extends StatelessWidget {
  const _TimerPill({required this.controller});

  final ExamController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final (background, foreground) = switch (controller) {
      _ when controller.isCritical => (scheme.error, scheme.onError),
      _ when controller.isRunningOut => (
          BlueprintPalette.warningBg,
          const Color(0xFF7C4A03),
        ),
      _ => (scheme.surfaceContainerHigh, scheme.onSurface),
    };

    return Semantics(
      liveRegion: controller.isRunningOut,
      label: '${controller.formattedRemaining} remaining',
      child: AnimatedContainer(
        duration: Motion.base,
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s3,
          vertical: Tokens.s2,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(Tokens.rSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 16, color: foreground),
            const SizedBox(width: Tokens.s2),
            Text(
              controller.formattedRemaining,
              style: text.labelLarge?.copyWith(
                color: foreground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Question ───────────────────────────────────────────────────────────────

class _QuestionPage extends StatelessWidget {
  const _QuestionPage({
    required this.controller,
    required this.question,
  });

  final ExamController controller;
  final Question question;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chosen = controller.answerFor(question);
    final reveal = controller.config.revealsAnswers && chosen != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Tokens.s5,
        Tokens.s5,
        Tokens.s5,
        Tokens.s8,
      ),
      children: [
        Row(
          children: [
            if (question.topic != null && question.topic!.isNotEmpty)
              _MetaChip(icon: Icons.label_outline, label: question.topic!),
            if (question.year != null) ...[
              const SizedBox(width: Tokens.s2),
              _MetaChip(
                icon: Icons.calendar_today_outlined,
                label: '${question.year}',
              ),
            ],
          ],
        ),
        const SizedBox(height: Tokens.s4),
        // Selection is off: a selection gesture inside a horizontal PageView
        // swallows the swipe that moves to the next question. Review, which has
        // no PageView, keeps it.
        QuestionBody(question: question),
        const SizedBox(height: Tokens.s6),
        for (final key in Question.optionKeys)
          if (question.options[key] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s3),
              child: OptionTile(
                optionKey: key,
                label: question.options[key]!,
                selected: chosen == key,
                // Nothing is right or wrong on screen until practice mode says
                // so; a timed exam gives no tells.
                correct: reveal ? key == question.answerKey : null,
                onTap: () => controller.select(question, key),
              ),
            ),
        if (reveal) ...[
          const SizedBox(height: Tokens.s3),
          _Explanation(question: question, correct: chosen == question.answerKey),
        ],
        const SizedBox(height: Tokens.s5),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: Tokens.s2,
            children: [
              if (chosen != null && !controller.config.revealsAnswers)
                TextButton.icon(
                  onPressed: () => controller.clearAnswer(question),
                  icon: const Icon(Icons.backspace_outlined, size: 18),
                  label: const Text('Clear answer'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                ),
              // Reporting a bad question. The same button is on the corrections
              // screen, where a wrong answer key is far easier to spot.
              ReportQuestionButton(
                question: question,
                // The question's own subject, not the page's: a PageView builds
                // its neighbours, so the tile being reported is not always the
                // one the controller's index is pointing at.
                subject: question.subject.isNotEmpty
                    ? question.subject
                    : controller.config.subject,
                examMode: controller.config.exam,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s3,
          vertical: Tokens.s1,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Tokens.rXs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: scheme.onSurfaceVariant),
            const SizedBox(width: Tokens.s1),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Practice-mode feedback panel, shown the moment an answer is chosen.
class _Explanation extends StatelessWidget {
  const _Explanation({required this.question, required this.correct});

  final Question question;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tone = correct ? scheme.tertiaryContainer : scheme.errorContainer;
    final onTone = correct ? scheme.onTertiaryContainer : scheme.onErrorContainer;
    final explanation = question.explanation;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(Tokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                correct ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 20,
                color: onTone,
              ),
              const SizedBox(width: Tokens.s2),
              Text(
                correct
                    ? 'Correct'
                    : 'The answer is ${question.answerKey.toUpperCase()}',
                style: text.titleSmall?.copyWith(color: onTone),
              ),
            ],
          ),
          if (explanation != null && explanation.isNotEmpty) ...[
            const SizedBox(height: Tokens.s2),
            Text(
              explanation,
              style: text.bodyMedium?.copyWith(color: onTone),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Toolbar ────────────────────────────────────────────────────────────────

class _ExamToolbar extends StatelessWidget {
  const _ExamToolbar({
    required this.controller,
    required this.onPalette,
    required this.onSubmit,
  });

  final ExamController controller;
  final VoidCallback onPalette;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s4,
          Tokens.s3,
          Tokens.s4,
          Tokens.s3,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            IconButton.filledTonal(
              onPressed: controller.isFirst ? null : controller.previous,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous question',
            ),
            const SizedBox(width: Tokens.s2),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPalette,
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                label: Text(
                  '${controller.answeredCount}/${controller.total} answered',
                ),
              ),
            ),
            const SizedBox(width: Tokens.s2),
            // Submit is reachable from every question, not just the last one: a
            // student who has finished the questions they can do should not have
            // to page through the rest to hand the paper in. The web keeps it in
            // the topbar for the same reason.
            if (controller.isLast)
              FilledButton(
                onPressed: controller.isSubmitting ? null : onSubmit,
                child: controller.isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit'),
              )
            else ...[
              IconButton.filled(
                onPressed: controller.next,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next question',
              ),
              const SizedBox(width: Tokens.s2),
              IconButton.filledTonal(
                onPressed: controller.isSubmitting ? null : onSubmit,
                icon: const Icon(Icons.send_rounded, size: 18),
                tooltip: 'Submit exam',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
