import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/gamification_repository.dart';
import '../../data/services/mission_signals.dart';
import '../../domain/models/leaderboard_entry.dart';
import '../../domain/models/xp_result.dart';
import '../core/format.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/ruled_paper.dart';
import '../core/widgets/skeleton.dart';

/// The honour roll.
///
/// Port of `src/pages/dashboard/LeaderboardView.jsx`. The web renders a table;
/// a phone gets the same rows as a list, because five columns on a handset means
/// either horizontal scrolling or unreadable text.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry> _entries = const [];
  int? _myRank;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final gamification = context.read<GamificationRepository>();
    final session = context.read<SessionController>();
    final uid = session.account?.uid;

    // Both at once, as the web does — the rank call is also what unlocks the
    // Top 10 / Top 50 achievements, so it must fire even if the list is cached.
    final results = await Future.wait([
      gamification.leaderboard(),
      gamification.myRank().then<MyRank?>((r) => r).catchError((_) => null),
    ]);

    if (!mounted) return;
    final entries = results[0] as List<LeaderboardEntry>;
    final rank = results[1] as MyRank?;

    setState(() {
      _entries = entries;
      // The backend's rank is authoritative. Without it, fall back to finding
      // ourselves in the list we did get.
      _myRank = rank?.rank ??
          (() {
            final i = entries.indexWhere((e) => e.uid == uid);
            return i >= 0 ? i + 1 : null;
          })();
      _loading = false;
    });

    if (rank != null) {
      unawaitedMissionSignal(context, uid);
      for (final id in rank.newAchievements) {
        final label = Achievements.labels[id];
        if (label != null) {
          showToast('Achievement unlocked: $label!',
              variant: ToastVariant.success);
        }
      }
    }
  }

  /// Visiting the leaderboard is itself a daily mission on the web.
  static void unawaitedMissionSignal(BuildContext context, String? uid) {
    context.read<MissionSignals>().set('leaderboard', uid);
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.select<SessionController, String?>(
      (s) => s.account?.uid,
    );

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _loading = true);
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
            title: 'Leaderboard',
            subtitle: 'The NLTC honour roll — top 50 students ranked by XP '
                'earned.',
          ),
          if (_myRank != null) _MyRankCard(rank: _myRank!),
          AppCard(
            title: 'Honour Roll — Top 50',
            titleIcon: Icons.emoji_events_rounded,
            padding: EdgeInsets.zero,
            child: _loading
                ? const SkeletonTable(rows: 10)
                : _entries.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: Tokens.s6),
                        child: EmptyState(
                          icon: Icons.emoji_events_outlined,
                          title: 'No rankings yet',
                          message:
                              'Start studying to appear on the leaderboard!',
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < _entries.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            _LeaderboardRow(
                              entry: _entries[i],
                              isMe: _entries[i].uid == uid,
                            ),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

/// `.lb-me` — the student's own standing, on ruled paper with a brand spine.
class _MyRankCard extends StatelessWidget {
  const _MyRankCard({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? scheme.surfaceContainerLow : BlueprintPalette.white,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        border: Border(
          left: BorderSide(color: scheme.primary, width: 4),
          top: BorderSide(color: scheme.outlineVariant),
          right: BorderSide(color: scheme.outlineVariant),
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: RuledPaper(
        lineSpacing: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s4,
            vertical: 13,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? scheme.primaryContainer
                      : BlueprintPalette.b100,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.my_location_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Your Rank: #$rank',
                      style: GoogleFonts.fraunces(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Keep studying to climb higher!',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry, required this.isMe});

  final LeaderboardEntry entry;
  final bool isMe;

  /// The web shows `#1`–`#3` for the podium; the medals read better on a phone
  /// and carry the same ranking without needing a colour to explain it.
  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onPodium = entry.rank >= 1 && entry.rank <= 3;

    return Container(
      color: isMe
          ? (isDark
              ? scheme.primaryContainer.withValues(alpha: 0.35)
              : BlueprintPalette.b100)
          : onPodium
              ? (isDark ? scheme.surfaceContainerLow : BlueprintPalette.b50)
              : null,
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s3,
        vertical: 11,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: onPodium
                ? Text(
                    _medals[entry.rank - 1],
                    style: const TextStyle(fontSize: 17),
                  )
                : Text(
                    '#${entry.rank}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          // `.lb-avatar`
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [BlueprintPalette.b600, BlueprintPalette.b400],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              entry.initial,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: BlueprintPalette.white,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(You)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      entry.exam,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (entry.state != null) ...[
                      Text(
                        ' · ${entry.state}',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Tokens.s2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                thousands(entry.xp),
                style: GoogleFonts.fraunces(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 2),
              AppBadge(label: entry.levelName, tone: BadgeTone.gold),
            ],
          ),
        ],
      ),
    );
  }
}
