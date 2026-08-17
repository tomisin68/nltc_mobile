import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/live_repository.dart';
import '../../data/services/mission_signals.dart';
import '../../domain/models/live_session.dart';
import '../../domain/pro_features.dart';
import '../core/state/session_controller.dart';
import '../core/state/xp_service.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/pro_gate.dart';
import '../core/widgets/skeleton.dart';
import 'livestream_screen.dart';

/// The live hall.
///
/// Port of `LiveClassesView`: the class that is on right now gets the marquee, and
/// everything else is a card below it, filterable by state.
class LiveClassesScreen extends StatefulWidget {
  const LiveClassesScreen({super.key});

  @override
  State<LiveClassesScreen> createState() => _LiveClassesScreenState();
}

enum _LiveFilter {
  all('All'),
  live('Live now'),
  scheduled('Upcoming'),
  ended('Past');

  const _LiveFilter(this.label);
  final String label;
}

class _LiveClassesScreenState extends State<LiveClassesScreen> {
  StreamSubscription<List<LiveSession>>? _subscription;
  List<LiveSession>? _sessions;
  _LiveFilter _filter = _LiveFilter.all;

  /// Rebuilds the countdowns without waiting for a Firestore write.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final isJunior =
        context.read<SessionController>().profile?.isJunior ?? false;
    _subscription = context
        .read<LiveRepository>()
        .watchSessions(isJunior: isJunior)
        .listen(
          (sessions) => setState(() => _sessions = sessions),
          onError: (_) => setState(() => _sessions = const []),
        );
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _join(LiveSession session) async {
    final controller = context.read<SessionController>();
    // Re-read on the tap: the button can sit on screen across the boundary, and a
    // sub-second stale render must not buy a session. `isPro`, not `active` — a
    // trial is active and still does not include live classes.
    if (!controller.access.isPro) {
      await showProUpsell(context, ProFeature.liveClasses);
      return;
    }
    if (session.channel.isEmpty) {
      showToast(
        'This class has no room set up yet — ask your tutor.',
        variant: ToastVariant.error,
      );
      return;
    }

    unawaited(
      context
          .read<XpService>()
          .award('join_live', meta: {'sessionId': session.id}),
    );
    await context.read<MissionSignals>().set('join_live', controller.account?.uid);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LivestreamScreen(sessionId: session.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    // The shell shows the upsell in place of this whole screen to a free
    // account, so in practice this is only false for the frame after a plan
    // lapses while the list is open — which is exactly when the banner and the
    // guard in [_join] earn their keep.
    final isPro = context.select<SessionController, bool>(
      (s) => s.access.isPro,
    );

    if (sessions == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
        children: const [
          PageHeader(
            title: 'Live Classes',
            subtitle: 'Face-to-face sessions with your tutors — ask questions, '
                'answer polls, get it cleared up on the spot.',
          ),
          SkeletonListItem(lines: 3),
          SizedBox(height: Tokens.s3),
          SkeletonListItem(lines: 2),
          SizedBox(height: Tokens.s3),
          SkeletonListItem(lines: 2),
        ],
      );
    }

    final liveNow = sessions.where((s) => s.isLive).toList();
    final marquee = liveNow.firstOrNull;
    final rail = sessions.where((s) {
      if (s.id == marquee?.id) return false;
      return switch (_filter) {
        _LiveFilter.all => true,
        _LiveFilter.live => s.isLive,
        _LiveFilter.scheduled => s.isScheduled,
        _LiveFilter.ended => s.hasEnded,
      };
    }).toList();

    final counts = {
      _LiveFilter.all: sessions.length,
      _LiveFilter.live: liveNow.length,
      _LiveFilter.scheduled: sessions.where((s) => s.isScheduled).length,
      _LiveFilter.ended: sessions.where((s) => s.hasEnded).length,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
      children: [
        const PageHeader(
          title: 'Live Classes',
          subtitle: 'Face-to-face sessions with your tutors — ask questions, '
              'answer polls, get it cleared up on the spot.',
        ),
        if (marquee != null) ...[
          _Marquee(session: marquee, onJoin: () => _join(marquee)),
          const SizedBox(height: Tokens.s4),
        ],
        if (!isPro) ...[
          const _ProLock(),
          const SizedBox(height: Tokens.s4),
        ],
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _LiveFilter.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: Tokens.s2),
            itemBuilder: (context, i) {
              final filter = _LiveFilter.values[i];
              final count = counts[filter] ?? 0;
              return ChoiceChip(
                label: Text(count > 0 ? '${filter.label} · $count' : filter.label),
                selected: _filter == filter,
                onSelected: (_) => setState(() => _filter = filter),
              );
            },
          ),
        ),
        const SizedBox(height: Tokens.s4),
        if (rail.isEmpty)
          EmptyState(
            icon: Icons.satellite_alt_rounded,
            title: _emptyTitle(marquee != null),
            message: _emptyBody(marquee != null),
          )
        else
          for (final session in rail)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s3),
              child: _SessionCard(
                session: session,
                onJoin: () => _join(session),
              ),
            ),
      ],
    );
  }

  String _emptyTitle(bool hasMarquee) => switch (_filter) {
        _LiveFilter.live => hasMarquee
            ? 'That is the only class live'
            : 'Nothing live right now',
        _LiveFilter.scheduled => 'No classes scheduled yet',
        _LiveFilter.ended => 'No past sessions',
        _LiveFilter.all => 'No classes here yet',
      };

  String _emptyBody(bool hasMarquee) => switch (_filter) {
        _LiveFilter.live => hasMarquee
            ? 'Your tutor is running one session at the moment — jump into it '
                'above.'
            : 'Check the upcoming tab for what your tutors have lined up.',
        _LiveFilter.scheduled =>
          'New sessions appear here as soon as a tutor puts one on the timetable.',
        _LiveFilter.ended => 'Once a class wraps up it will be listed here.',
        _LiveFilter.all =>
          'Live classes will show up here the moment a tutor opens one.',
      };
}

/// The banner for the class that is on right now.
class _Marquee extends StatelessWidget {
  const _Marquee({required this.session, required this.onJoin});

  final LiveSession session;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(
          color: scheme.error.withValues(alpha: 0.35),
          width: 1.5,
        ),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            scheme.errorContainer.withValues(alpha: 0.4),
            scheme.surfaceContainerLowest,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.error,
              borderRadius: BorderRadius.circular(100),
            ),
            child: const Text(
              'LIVE NOW',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: Tokens.s3),
          Text(
            session.title,
            style: GoogleFonts.fraunces(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: Tokens.s3,
            runSpacing: 4,
            children: [
              if (session.subject != null)
                _MetaLine(
                  icon: Icons.menu_book_rounded,
                  label: session.subject!,
                ),
              if (session.hostName != null)
                _MetaLine(icon: Icons.person_rounded, label: session.hostName!),
              _MetaLine(
                icon: Icons.group_rounded,
                label: '${session.watching} watching',
              ),
            ],
          ),
          const SizedBox(height: Tokens.s4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onJoin,
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Join now'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ProLock extends StatelessWidget {
  const _ProLock();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Tokens.rMd),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live classes are a Pro feature',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Upgrade to sit in on live sessions, put your hand up and '
                  'answer polls in real time.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
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

/// One class in the rail.
class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onJoin});

  final LiveSession session;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final startsAt = session.scheduledAt;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        border: Border.all(
          color: session.isLive
              ? scheme.error.withValues(alpha: 0.35)
              : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s3,
              vertical: Tokens.s2,
            ),
            color: scheme.surfaceContainerHigh,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    session.subject ?? 'General',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (session.isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.error,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: Colors.white,
                      ),
                    ),
                  )
                else if (session.isScheduled && startsAt != null)
                  Text(
                    startsAt.isAfter(DateTime.now())
                        ? 'in ${_countdown(startsAt.difference(DateTime.now()))}'
                        : 'starting',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Tokens.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: Tokens.s3,
                  runSpacing: 3,
                  children: [
                    if (session.hostName != null)
                      _MetaLine(
                        icon: Icons.person_rounded,
                        label: session.hostName!,
                      ),
                    if (session.isLive)
                      _MetaLine(
                        icon: Icons.group_rounded,
                        label: '${session.watching} watching',
                      ),
                    if (session.isScheduled && startsAt != null)
                      _MetaLine(
                        icon: Icons.calendar_today_rounded,
                        label: DateFormat('EEE d MMM · h:mm a').format(startsAt),
                      ),
                    if (session.hasEnded)
                      const _MetaLine(
                        icon: Icons.history_rounded,
                        label: 'Finished',
                      ),
                  ],
                ),
                if (session.isLive) ...[
                  const SizedBox(height: Tokens.s3),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onJoin,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Join'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _countdown(Duration until) {
    final minutes = until.inMinutes;
    final days = minutes ~/ 1440;
    final hours = (minutes % 1440) ~/ 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes % 60}m';
    return '${minutes < 1 ? 1 : minutes}m';
  }
}
