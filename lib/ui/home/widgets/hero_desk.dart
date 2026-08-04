import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/profile_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/gamification.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/app_palette.dart';
import '../../core/toast.dart';
import '../../core/widgets/ruled_paper.dart';

/// The top of the study desk.
///
/// Port of `HeroDesk`: a sheet of ruled paper with the date written across it, a
/// greeting by name, the level bar, and — down the side — the exam countdown and
/// the three numbers a student checks first.
class HeroDesk extends StatelessWidget {
  const HeroDesk({
    super.key,
    required this.profile,
    required this.rank,
    required this.loadingRank,
    required this.sessionsThisWeek,
  });

  final AppUser? profile;

  /// Null when the student has no rank yet, or the read failed.
  final int? rank;
  final bool loadingRank;
  final int sessionsThisWeek;

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// The line under the greeting: whichever fact about this student is most worth
  /// saying today. Same precedence as the web — streak, then this week's effort,
  /// then a nudge.
  String _subline() {
    final streak = profile?.streak ?? 0;
    if (streak >= 3) {
      return "You're on a $streak-day streak — don't break the chain!";
    }
    if (sessionsThisWeek > 0) {
      return '$sessionsThisWeek practice session'
          '${sessionsThisWeek == 1 ? '' : 's'} this week. '
          'Keep the momentum going!';
    }
    return profile?.isJunior ?? false
        ? 'Your BECE success starts here — one topic at a time.'
        : 'Every session brings you closer to your target score.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final xp = profile?.xp ?? 0;
    final level = Levels.forXp(xp);
    final nextXp = Levels.nextLevelXp(xp);
    final progress = Levels.progressInLevel(xp);
    final numbers = NumberFormat.decimalPattern();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: RuledPaper(
        lineSpacing: 35,
        // The exercise-book margin line, which is what makes this read as paper
        // rather than as a coloured box.
        marginRuleAt: 22,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(34, 16, Tokens.s4, Tokens.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                style: GoogleFonts.caveat(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: BlueprintPalette.b500,
                ),
              ),
              const SizedBox(height: 6),
              // The name is italic here exactly as `.dh-greet em` is on the web.
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${_greeting()}, '),
                    TextSpan(
                      text: profile?.firstName ?? 'Student',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: scheme.primary,
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
                style: GoogleFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  height: 1.15,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _subline(),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Tokens.s4),

              // ── Level bar ──
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: BlueprintPalette.b800,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'Lv $level · ${Levels.nameForXp(xp)}',
                      style: GoogleFonts.fraunces(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: progress),
                        duration: const Duration(milliseconds: 800),
                        curve: Motion.emphasized,
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: 7,
                          backgroundColor: BlueprintPalette.b100,
                          valueColor: const AlwaysStoppedAnimation(
                            BlueprintPalette.b500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${numbers.format(xp)} / ${numbers.format(nextXp)} XP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Tokens.s4),

              ExamCountdown(profile: profile),
              const SizedBox(height: Tokens.s3),

              // ── The three numbers ──
              Row(
                children: [
                  Expanded(
                    child: _StatChip(
                      icon: Icons.local_fire_department_rounded,
                      value: '${profile?.streak ?? 0}',
                      label: 'Streak',
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                  Expanded(
                    child: _StatChip(
                      icon: Icons.star_rounded,
                      value: numbers.format(xp),
                      label: 'XP',
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                  Expanded(
                    child: _StatChip(
                      icon: Icons.emoji_events_rounded,
                      value: loadingRank ? '…' : (rank != null ? '#$rank' : '—'),
                      label: 'Rank',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? scheme.surfaceContainerHigh : BlueprintPalette.b50,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        border: Border.all(
          color: isDark ? scheme.outlineVariant : BlueprintPalette.b100,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: scheme.primary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  value,
                  style: GoogleFonts.fraunces(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    letterSpacing: -0.3,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The exam-day countdown chip, and the sheet that sets it.
///
/// Port of `ExamCountdown`. A student with no date set sees a dashed invitation
/// to add one; inside a fortnight the chip turns red, because at that point the
/// number is the most important thing on the screen.
class ExamCountdown extends StatelessWidget {
  const ExamCountdown({super.key, required this.profile});

  final AppUser? profile;

  static const examOptions = [
    'JAMB',
    'WAEC',
    'NECO',
    'Post-UTME',
    'BECE',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final examDate = profile?.examDate == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(profile!.examDate!);

    final daysLeft = examDate == null
        ? null
        : DateTime(examDate.year, examDate.month, examDate.day)
            .difference(DateTime.now().copyWith(
              hour: 0,
              minute: 0,
              second: 0,
              millisecond: 0,
              microsecond: 0,
            ))
            .inDays;

    final isSet = daysLeft != null && daysLeft >= 0;
    final urgent = isSet && daysLeft <= 14;

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: isSet
            ? (urgent ? const Color(0xFFB91C1C) : BlueprintPalette.b800)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          onTap: () => _openEditor(context),
          borderRadius: BorderRadius.circular(100),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s4,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              border: isSet
                  ? null
                  : Border.all(
                      color: BlueprintPalette.b300,
                      width: 1.5,
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSet ? Icons.adjust_rounded : Icons.event_available_rounded,
                  size: 14,
                  color: isSet ? Colors.white : scheme.primary,
                ),
                const SizedBox(width: Tokens.s2),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: isSet
                          ? [
                              TextSpan(
                                text: '$daysLeft',
                                style: GoogleFonts.fraunces(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              TextSpan(
                                text: ' day${daysLeft == 1 ? '' : 's'} to '
                                    '${profile?.examName ?? 'exam'}',
                              ),
                            ]
                          : [
                              TextSpan(
                                text: examDate != null
                                    ? 'Exam passed — set your next one'
                                    : 'Set your exam date',
                              ),
                            ],
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: isSet ? Colors.white : scheme.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ExamCountdownSheet(profile: profile),
      );
}

class _ExamCountdownSheet extends StatefulWidget {
  const _ExamCountdownSheet({required this.profile});

  final AppUser? profile;

  @override
  State<_ExamCountdownSheet> createState() => _ExamCountdownSheetState();
}

class _ExamCountdownSheetState extends State<_ExamCountdownSheet> {
  late String _name;
  DateTime? _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.profile?.examName;
    _name = ExamCountdown.examOptions.contains(saved)
        ? saved!
        : ExamCountdown.examOptions.first;
    final ms = widget.profile?.examDate;
    _date = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 30)),
      // No point counting down to a date that has been and gone.
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: 'When is your exam?',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final uid = context.read<SessionController>().account?.uid;
    final date = _date;
    if (uid == null || date == null) return;

    setState(() => _saving = true);
    try {
      await context.read<ProfileRepository>().setExamCountdown(uid, _name, date);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast('Counting down to $_name — good luck! 🎯',
          variant: ToastVariant.success);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(
        'Could not save your exam date. Please try again.',
        variant: ToastVariant.error,
      );
    }
  }

  Future<void> _clear() async {
    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      await context.read<ProfileRepository>().clearExamCountdown(uid);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast('Exam countdown removed.', variant: ToastVariant.success);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast('Could not remove the exam date.', variant: ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSavedDate = widget.profile?.examDate != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s5,
          Tokens.s2,
          Tokens.s5,
          Tokens.s6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.adjust_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Count down to exam day',
                  style: GoogleFonts.fraunces(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.s5),
            DropdownButtonFormField<String>(
              initialValue: _name,
              decoration: const InputDecoration(labelText: 'Exam'),
              items: [
                for (final option in ExamCountdown.examOptions)
                  DropdownMenuItem(value: option, child: Text(option)),
              ],
              onChanged: (value) =>
                  setState(() => _name = value ?? _name),
            ),
            const SizedBox(height: Tokens.s4),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(Tokens.rSm),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Exam date'),
                child: Text(
                  _date == null
                      ? 'Pick a date'
                      : DateFormat('EEEE, d MMMM yyyy').format(_date!),
                  style: TextStyle(
                    fontSize: 14,
                    color: _date == null
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Tokens.s5),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving || _date == null ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Save'),
                  ),
                ),
                if (hasSavedDate) ...[
                  const SizedBox(width: Tokens.s3),
                  OutlinedButton(
                    onPressed: _saving ? null : _clear,
                    child: const Text('Remove'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
