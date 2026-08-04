import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/broadcast_repository.dart';
import '../../domain/models/broadcast.dart';
import '../core/format.dart';
import '../core/state/notification_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/ruled_paper.dart';
import '../core/widgets/skeleton.dart';
import '../shell/dashboard_sidebar.dart' show DashboardSidebar;

/// The notice board.
///
/// Port of `src/pages/dashboard/AnnouncementsView.jsx`. Each announcement is a
/// pinned note on ruled paper, tilted very slightly — the `.nb-note` treatment,
/// alternating the tilt by position so a column of them doesn't look mechanical.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<Broadcast> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // Opening the board is what marks the inbox read, exactly as on the web —
    // the announcements *are* the notifications.
    context.read<NotificationController>().markAllRead();
  }

  Future<void> _load() async {
    final items = await context.read<BroadcastRepository>().recent();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isJunior = DashboardSidebar.isJuniorStudent(
      context.select<SessionController, dynamic>((s) => s.profile),
    );
    final visible =
        _items.where((b) => b.visibleTo(isJunior: isJunior)).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s4,
          0,
          Tokens.s4,
          Tokens.s10,
        ),
        children: [
          const PageHeader(
            title: 'Notice Board',
            subtitle: 'Announcements pinned by your tutors — newest first.',
          ),
          if (_loading)
            AppCard(
              child: Column(
                children: [
                  for (var i = 0; i < 4; i++) const SkeletonListItem(lines: 3),
                ],
              ),
            )
          else if (visible.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.push_pin_outlined,
                title: 'Nothing pinned yet',
                message: 'Check back soon — announcements from your tutors '
                    'will appear here.',
              ),
            )
          else
            for (var i = 0; i < visible.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _PinnedNote(
                  broadcast: visible[i],
                  // `.nb-note:nth-child(odd|even)`
                  tiltDegrees: i.isEven ? -0.45 : 0.4,
                ),
              ),
        ],
      ),
    );
  }
}

/// `.nb-note` — a note pinned to the board.
class _PinnedNote extends StatelessWidget {
  const _PinnedNote({required this.broadcast, required this.tiltDegrees});

  final Broadcast broadcast;
  final double tiltDegrees;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // The admin's audience label is only worth showing when it isn't everyone.
    final sentTo = broadcast.sentTo;
    final showSentTo = sentTo != null && sentTo != 'All Users';

    return Transform.rotate(
      angle: tiltDegrees * 3.1415926535 / 180,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? scheme.surfaceContainerLow : BlueprintPalette.white,
          // Squarer than the app's other cards — it is paper, not a panel.
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: RuledPaper(
          lineSpacing: 32,
          child: Stack(
            children: [
              Padding(
                // Extra headroom for the pin.
                padding: const EdgeInsets.fromLTRB(Tokens.s4, 22, Tokens.s4, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            broadcast.title,
                            style: GoogleFonts.fraunces(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                              letterSpacing: -0.15,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        if (showSentTo) ...[
                          const SizedBox(width: Tokens.s2),
                          AppBadge(label: sentTo, tone: BadgeTone.gold),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (broadcast.imageUrl != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Tokens.rXs),
                        child: Image.network(
                          broadcast.imageUrl!,
                          fit: BoxFit.cover,
                          // A dead image URL must not take the announcement text
                          // down with it.
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(height: Tokens.s2),
                    ],
                    Text(
                      broadcast.message,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.65,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      broadcast.createdAt == null
                          ? '— posted'
                          : '— posted ${relativeTime(broadcast.createdAt!)}',
                      // `.nb-note-time` is handwritten, like a margin note.
                      style: GoogleFonts.caveat(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? scheme.primary : BlueprintPalette.b500,
                      ),
                    ),
                  ],
                ),
              ),
              // `.nb-note::before` — the board pin.
              Positioned(
                top: 9,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(-0.3, -0.4),
                        colors: [BlueprintPalette.b300, BlueprintPalette.b600],
                        stops: [0, 0.7],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: BlueprintPalette.b900.withValues(alpha: 0.35),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
