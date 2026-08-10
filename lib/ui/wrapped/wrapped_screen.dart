import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/wrapped_repository.dart';
import '../../data/services/prefs_service.dart';
import '../../domain/models/wrapped_stats.dart';
import '../../domain/referral.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import 'wrapped_card.dart';
import 'wrapped_share.dart';

/// The monthly recap, told as a short story.
///
/// A sequence of panels rather than one scrolling page, because the point of a
/// Wrapped is the reveal — a number you have to scroll past is just a
/// dashboard. The last panel is the shareable card, which is the only panel
/// that has to exist; everything before it is there to earn the share.
class WrappedScreen extends StatefulWidget {
  const WrappedScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const WrappedScreen(),
        fullscreenDialog: true,
      );

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends State<WrappedScreen> {
  final _controller = PageController();
  final _cardKey = GlobalKey();

  WrappedReport? _report;
  DateTime? _month;
  bool _loading = true;
  bool _sharing = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    final report = await context.read<WrappedRepository>().load(
          uid: uid,
          streak: session.profile?.streak ?? 0,
          xp: session.profile?.xp ?? 0,
        );
    if (!mounted) return;

    final month = report.defaultMonth;
    setState(() {
      _report = report;
      _month = month;
      _loading = false;
    });

    // Clears the sidebar's "new recap" dot. Recorded against the last finished
    // month rather than whichever month is on screen, because that dot only
    // ever means "the month that just ended is ready" — browsing back to March
    // is not an answer to it, and neither is a new account whose only month is
    // the one still running.
    final now = DateTime.now();
    if (!mounted) return;
    await context
        .read<PrefsService>()
        .setWrappedSeen(monthKeyFor(DateTime(now.year, now.month - 1)));
  }

  /// Months the arrows can reach: whatever has data, and always this month, so
  /// a student who has just started can still see their recap filling up.
  List<DateTime> get _months {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    final months = List<DateTime>.from(_report?.months ?? const <DateTime>[]);
    if (!months.any((m) => m.year == current.year && m.month == current.month)) {
      months.insert(0, current);
    }
    return months;
  }

  void _stepMonth(int delta) {
    final months = _months;
    final month = _month;
    if (month == null) return;
    final index = months.indexWhere(
      (m) => m.year == month.year && m.month == month.month,
    );
    final next = index + delta;
    if (next < 0 || next >= months.length) return;

    HapticFeedback.selectionClick();
    setState(() => _month = months[next]);
    _controller.jumpToPage(0);
    setState(() => _page = 0);
  }

  void _advance(int delta) {
    final target = _page + delta;
    if (target < 0 || target >= _panelCount) return;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  int get _panelCount => 5;

  Future<void> _share(WrappedStats stats) async {
    if (_sharing) return;
    setState(() => _sharing = true);

    final uid = context.read<SessionController>().account?.uid;
    final ok = await WrappedShare.shareCard(
      boundaryKey: _cardKey,
      message: inviteMessage(
        title: stats.title,
        monthLabel: stats.monthLabel,
        uid: uid,
      ),
      fileName: 'nltc-wrapped-${stats.monthKey}.png',
    );

    if (!mounted) return;
    setState(() => _sharing = false);
    if (!ok) {
      showToast('Could not build your card. Try again.',
          variant: ToastVariant.error);
    }
  }

  Future<void> _copyLink() async {
    final uid = context.read<SessionController>().account?.uid;
    await Clipboard.setData(ClipboardData(text: inviteLink(uid)));
    showToast('Invite link copied.');
  }

  @override
  Widget build(BuildContext context) {
    final month = _month;
    final report = _report;
    final stats = (report != null && month != null)
        ? report.forMonth(month)
        : null;

    return Scaffold(
      backgroundColor: BlueprintPalette.ink,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: BlueprintPalette.b300),
              )
            : stats == null
                ? const _Unavailable()
                : Column(
                    children: [
                      _Progress(count: _panelCount, active: _page),
                      _MonthBar(
                        label: stats.monthLabel,
                        onPrevious: () => _stepMonth(1),
                        onNext: () => _stepMonth(-1),
                        onClose: () => Navigator.of(context).pop(),
                      ),
                      if (report!.isOfflineFallback)
                        const _OfflineNote(),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapUp: (details) {
                            final width = MediaQuery.sizeOf(context).width;
                            _advance(details.localPosition.dx < width * 0.3
                                ? -1
                                : 1);
                          },
                          child: PageView(
                            controller: _controller,
                            onPageChanged: (i) => setState(() => _page = i),
                            children: [
                              _OpeningPanel(stats: stats, active: _page == 0),
                              _VolumePanel(stats: stats, active: _page == 1),
                              _SubjectsPanel(stats: stats, active: _page == 2),
                              _BestPanel(stats: stats, active: _page == 3),
                              _CardPanel(
                                stats: stats,
                                cardKey: _cardKey,
                                name: context
                                        .read<SessionController>()
                                        .profile
                                        ?.firstName ??
                                    '',
                                sharing: _sharing,
                                onShare: () => _share(stats),
                                onCopyLink: _copyLink,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ─── Chrome ──────────────────────────────────────────────────────────────────

/// Story-style segments across the top.
class _Progress extends StatelessWidget {
  const _Progress({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s3, Tokens.s4, 0),
        child: Row(
          children: [
            for (var i = 0; i < count; i++)
              Expanded(
                child: AnimatedContainer(
                  duration: Motion.fast,
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i <= active
                        ? BlueprintPalette.white
                        : const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.s2, Tokens.s2, Tokens.s2, 0),
        child: Row(
          children: [
            IconButton(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
              color: BlueprintPalette.b300,
              tooltip: 'Earlier month',
            ),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.syne(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: BlueprintPalette.white,
                ),
              ),
            ),
            IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded),
              color: BlueprintPalette.b300,
              tooltip: 'Later month',
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
              color: BlueprintPalette.b300,
              tooltip: 'Close',
            ),
          ],
        ),
      );
}

class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s2, Tokens.s4, 0),
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s3,
          vertical: Tokens.s2,
        ),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(Tokens.rSm),
        ),
        child: const Text(
          'Counted from this phone only — reconnect to include tests you sat '
          'on the website.',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.4,
            color: BlueprintPalette.b200,
          ),
        ),
      );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: BlueprintPalette.b300, size: 40),
              const SizedBox(height: Tokens.s4),
              const Text(
                'Your Wrapped is not ready yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: BlueprintPalette.white,
                ),
              ),
              const SizedBox(height: Tokens.s2),
              const Text(
                'Sit a test or two and come back — there is nothing to recap '
                'yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: BlueprintPalette.b200,
                ),
              ),
              const SizedBox(height: Tokens.s5),
              Builder(
                builder: (context) => OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BlueprintPalette.white,
                    side: const BorderSide(color: Color(0x44FFFFFF)),
                  ),
                  child: const Text('Back'),
                ),
              ),
            ],
          ),
        ),
      );
}

// ─── Panels ──────────────────────────────────────────────────────────────────

/// Fades and lifts its child in once the panel becomes the visible one.
///
/// Tied to [active] rather than to being built, because a PageView builds the
/// neighbouring panel before it is on screen — animating on build would play
/// every reveal to nobody.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.active,
    required this.child,
    this.delay = Duration.zero,
  });

  final bool active;
  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: active ? 1 : 0),
        duration: Duration(milliseconds: 420) + delay,
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 18),
            child: child,
          ),
        ),
        child: child,
      );
}

/// Common frame: generous padding, content pinned to the bottom third the way
/// a story panel is, so the eye lands in the same place on every page.
class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s6,
          Tokens.s6,
          Tokens.s6,
          Tokens.s10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        ),
      );
}

class _Kicker extends StatelessWidget {
  const _Kicker(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: GoogleFonts.syne(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: BlueprintPalette.b300,
        ),
      );
}

class _Headline extends StatelessWidget {
  const _Headline(this.text, {this.size = 34});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.fraunces(
          fontSize: size,
          height: 1.08,
          fontWeight: FontWeight.w900,
          color: BlueprintPalette.white,
        ),
      );
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          height: 1.6,
          color: BlueprintPalette.b200,
        ),
      );
}

class _OpeningPanel extends StatelessWidget {
  const _OpeningPanel({required this.stats, required this.active});

  final WrappedStats stats;
  final bool active;

  @override
  Widget build(BuildContext context) => _Panel(
        children: [
          _Reveal(active: active, child: const _Kicker('NLTC Wrapped')),
          const SizedBox(height: Tokens.s3),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 90),
            child: _Headline('Your\n${stats.monthLabel},\nwrapped.', size: 40),
          ),
          const SizedBox(height: Tokens.s4),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 180),
            child: _Body(
              stats.isEmpty
                  ? 'This month is still blank. Sit a test and it starts '
                      'filling in.'
                  : 'Here is what that month actually looked like.',
            ),
          ),
          const SizedBox(height: Tokens.s6),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 260),
            child: Row(
              children: const [
                Icon(Icons.touch_app_rounded,
                    size: 15, color: BlueprintPalette.b300),
                SizedBox(width: Tokens.s2),
                Text(
                  'Tap to keep going',
                  style: TextStyle(fontSize: 11.5, color: BlueprintPalette.b300),
                ),
              ],
            ),
          ),
        ],
      );
}

class _VolumePanel extends StatelessWidget {
  const _VolumePanel({required this.stats, required this.active});

  final WrappedStats stats;
  final bool active;

  @override
  Widget build(BuildContext context) => _Panel(
        children: [
          _Reveal(active: active, child: const _Kicker('You answered')),
          const SizedBox(height: Tokens.s2),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 90),
            child: Text(
              '${stats.questions}',
              style: GoogleFonts.syne(
                fontSize: 76,
                height: 1,
                fontWeight: FontWeight.w800,
                color: BlueprintPalette.white,
              ),
            ),
          ),
          const SizedBox(height: Tokens.s1),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 140),
            child: _Headline('questions', size: 26),
          ),
          const SizedBox(height: Tokens.s5),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 220),
            child: _Body(
              stats.isEmpty
                  ? 'Nothing yet this month.'
                  : 'Across ${stats.sittings} '
                      '${stats.sittings == 1 ? 'test' : 'tests'}, on '
                      '${stats.activeDays} different '
                      '${stats.activeDays == 1 ? 'day' : 'days'}'
                      '${stats.timeStudied == null ? '' : ', for '
                          '${WrappedStats.formatDuration(stats.timeStudied!)} '
                          'of sitting time'}.',
            ),
          ),
        ],
      );
}

class _SubjectsPanel extends StatelessWidget {
  const _SubjectsPanel({required this.stats, required this.active});

  final WrappedStats stats;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final top = stats.subjects.take(5).toList();
    final most = top.isEmpty ? 1 : top.first.questions;

    return _Panel(
      children: [
        _Reveal(active: active, child: const _Kicker('Where the time went')),
        const SizedBox(height: Tokens.s3),
        if (top.isEmpty)
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 90),
            child: _Body('No subjects practised this month.'),
          )
        else ...[
          for (var i = 0; i < top.length; i++)
            _Reveal(
              active: active,
              delay: Duration(milliseconds: 90 + i * 70),
              child: Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s3),
                child: _SubjectBar(
                  tally: top[i],
                  fraction: top[i].questions / most,
                  rank: i + 1,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _SubjectBar extends StatelessWidget {
  const _SubjectBar({
    required this.tally,
    required this.fraction,
    required this.rank,
  });

  final SubjectTally tally;
  final double fraction;
  final int rank;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '$rank',
                  style: GoogleFonts.syne(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: BlueprintPalette.b300,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  tally.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: BlueprintPalette.white,
                  ),
                ),
              ),
              Text(
                '${tally.questions}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: BlueprintPalette.b200,
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s1),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.05, 1),
                minHeight: 6,
                backgroundColor: const Color(0x1AFFFFFF),
                valueColor: const AlwaysStoppedAnimation(BlueprintPalette.b400),
              ),
            ),
          ),
        ],
      );
}

class _BestPanel extends StatelessWidget {
  const _BestPanel({required this.stats, required this.active});

  final WrappedStats stats;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final sharpest = stats.sharpestSubject;

    return _Panel(
      children: [
        _Reveal(active: active, child: const _Kicker('Your best work')),
        const SizedBox(height: Tokens.s3),
        _Reveal(
          active: active,
          delay: const Duration(milliseconds: 90),
          child: _Headline(
            stats.bestScore == 0
                ? 'Still to come.'
                : '${stats.bestScore}% in\n${stats.bestScoreSubject}',
          ),
        ),
        const SizedBox(height: Tokens.s5),
        _Reveal(
          active: active,
          delay: const Duration(milliseconds: 180),
          child: _Body(
            stats.isEmpty
                ? 'Your best score shows up here once you have sat a full test.'
                : 'You answered ${stats.accuracy}% of everything correctly'
                    '${sharpest == null ? '' : ', and ${sharpest.subject} was '
                        'your sharpest at ${sharpest.accuracy}%'}.',
          ),
        ),
        if (stats.streak > 0) ...[
          const SizedBox(height: Tokens.s5),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 260),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department_rounded,
                    color: BlueprintPalette.warning, size: 20),
                const SizedBox(width: Tokens.s2),
                Text(
                  '${stats.streak}-day streak, still running',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: BlueprintPalette.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CardPanel extends StatelessWidget {
  const _CardPanel({
    required this.stats,
    required this.cardKey,
    required this.name,
    required this.sharing,
    required this.onShare,
    required this.onCopyLink,
  });

  final WrappedStats stats;
  final GlobalKey cardKey;
  final String name;
  final bool sharing;
  final VoidCallback onShare;
  final VoidCallback onCopyLink;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s5,
          Tokens.s4,
          Tokens.s5,
          Tokens.s6,
        ),
        child: Column(
          children: [
            // The boundary is exactly the card and nothing else, so the PNG has
            // no page background bleeding into its edges.
            RepaintBoundary(
              key: cardKey,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Tokens.rLg),
                child: WrappedCard(stats: stats, name: name),
              ),
            ),
            const SizedBox(height: Tokens.s5),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: sharing ? null : onShare,
                icon: sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(sharing ? 'Preparing…' : 'Share my Wrapped'),
                style: FilledButton.styleFrom(
                  backgroundColor: BlueprintPalette.b500,
                  foregroundColor: BlueprintPalette.white,
                  padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
                ),
              ),
            ),
            const SizedBox(height: Tokens.s2),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onCopyLink,
                icon: const Icon(Icons.link_rounded, size: 17),
                label: const Text('Copy my invite link'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BlueprintPalette.white,
                  side: const BorderSide(color: Color(0x44FFFFFF)),
                  padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
                ),
              ),
            ),
            const SizedBox(height: Tokens.s3),
            const Text(
              'Whoever joins through your link is counted as yours.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: BlueprintPalette.b300,
              ),
            ),
          ],
        ),
      );
}
