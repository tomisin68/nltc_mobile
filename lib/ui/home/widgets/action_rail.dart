import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/state/dashboard_controller.dart';
import '../../core/theme/app_palette.dart';

/// The quick-action rail — five index cards across the top of the desk.
///
/// Port of `ActionRail`. Each card is numbered in the corner in Caveat, the way a
/// student numbers their own list, and the set differs for the junior track
/// because BECE students have no video library or Post-UTME to go to.
class ActionRail extends StatelessWidget {
  const ActionRail({super.key, required this.isJunior});

  final bool isJunior;

  static const _senior = <_RailAction>[
    _RailAction(
      icon: Icons.laptop_mac_rounded,
      label: 'CBT Practice',
      hint: 'Timed exam sim',
      view: DashboardView.cbt,
    ),
    _RailAction(
      icon: Icons.bolt_rounded,
      label: 'Quick Test',
      hint: 'Short & sharp',
      view: DashboardView.quickTest,
    ),
    _RailAction(
      icon: Icons.play_circle_rounded,
      label: 'Video Lessons',
      hint: 'Watch & learn',
      view: DashboardView.lessons,
    ),
    _RailAction(
      icon: Icons.school_rounded,
      label: 'Official Quiz',
      hint: 'NLTC challenge',
      view: DashboardView.officialQuiz,
    ),
    _RailAction(
      icon: Icons.menu_book_rounded,
      label: 'Study Notes',
      hint: 'Read up a topic',
      view: DashboardView.notes,
    ),
  ];

  static const _junior = <_RailAction>[
    _RailAction(
      icon: Icons.school_rounded,
      label: 'BECE Practice',
      hint: 'Past questions',
      view: DashboardView.bece,
    ),
    _RailAction(
      icon: Icons.sensors_rounded,
      label: 'Live Classes',
      hint: 'Join a session',
      view: DashboardView.live,
    ),
    _RailAction(
      icon: Icons.menu_book_rounded,
      label: 'Study Notes',
      hint: 'Read up a topic',
      view: DashboardView.notes,
    ),
    _RailAction(
      icon: Icons.emoji_events_rounded,
      label: 'Leaderboard',
      hint: 'See the rankings',
      view: DashboardView.leaderboard,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final actions = isJunior ? _junior : _senior;

    // Two columns on a phone, which is where the web's own 768px breakpoint
    // lands. Deliberately not a horizontal rail: a card a student has to scroll
    // sideways to find is a card they never tap.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: Tokens.s2,
        crossAxisSpacing: Tokens.s2,
        mainAxisExtent: 96,
      ),
      itemCount: actions.length,
      itemBuilder: (context, i) => _RailCard(
        action: actions[i],
        number: '${i + 1}'.padLeft(2, '0'),
      ),
    );
  }
}

class _RailAction {
  const _RailAction({
    required this.icon,
    required this.label,
    required this.hint,
    required this.view,
  });

  final IconData icon;
  final String label;
  final String hint;
  final DashboardView view;
}

class _RailCard extends StatelessWidget {
  const _RailCard({required this.action, required this.number});

  final _RailAction action;
  final String number;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(Tokens.rMd),
      child: InkWell(
        onTap: () =>
            context.read<DashboardController>().select(action.view),
        borderRadius: BorderRadius.circular(Tokens.rMd),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.rMd),
            border: Border.all(color: scheme.outlineVariant),
            // The coloured top edge of an index card.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.035, 0.035],
              colors: [
                BlueprintPalette.b200,
                BlueprintPalette.b200,
                scheme.surfaceContainerLowest,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 0,
                child: Text(
                  number,
                  style: GoogleFonts.caveat(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: isDark
                        ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                        : BlueprintPalette.b200,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isDark
                          ? scheme.primaryContainer.withValues(alpha: 0.55)
                          : BlueprintPalette.b100,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: Icon(action.icon, size: 15, color: scheme.primary),
                  ),
                  const Spacer(),
                  Text(
                    action.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    action.hint,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
