import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/focus_timer.dart';
import '../core/widgets/notification_bell.dart';

/// The dashboard topbar — port of `.topbar` in
/// `src/components/layout/Topbar.css`.
///
/// A frosted paper strip with a pencil-rule bottom edge: hamburger, the current
/// view's title, the focus timer, a streak chip and the notification bell. The
/// handwritten date is deliberately absent — the web hides it under 768px too,
/// because the chips on the right need the room.
class DashboardTopbar extends StatelessWidget implements PreferredSizeWidget {
  const DashboardTopbar({super.key, required this.title});

  final String title;

  /// `--topbar-h`.
  static const _height = 60.0;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final streak = context.select<SessionController, int>(
      (s) => s.profile?.streak ?? 0,
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? scheme.surface : BlueprintPalette.white)
                .withValues(alpha: 0.92),
            border: Border(
              bottom: BorderSide(
                color: isDark ? scheme.outlineVariant : BlueprintPalette.b100,
                width: 2,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const _Hamburger(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.fraunces(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          height: 1.15,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const FocusTimer(),
                    if (streak > 0) ...[
                      const SizedBox(width: 8),
                      _StreakChip(streak: streak),
                    ],
                    const SizedBox(width: 4),
                    const NotificationBell(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.hamburger` — a bordered square with three rules, not Material's default
/// three-bar glyph, so the app and the website open their drawer with the same
/// button.
class _Hamburger extends StatelessWidget {
  const _Hamburger();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: 'Open menu',
      child: Material(
        color: isDark ? scheme.surfaceContainerLow : BlueprintPalette.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => Scaffold.of(context).openDrawer(),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outline, width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => Container(
                  width: 16,
                  height: 2,
                  margin: EdgeInsets.only(bottom: i == 2 ? 0 : 4),
                  decoration: BoxDecoration(
                    color: isDark ? scheme.onSurface : BlueprintPalette.b700,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.tb-streak` — the day-streak pill.
class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      label: '$streak day study streak',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? scheme.surfaceContainerHigh : BlueprintPalette.b100,
          border: Border.all(
            color: isDark ? scheme.outlineVariant : BlueprintPalette.b200,
          ),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              size: 13,
              color: isDark ? scheme.primary : BlueprintPalette.b500,
            ),
            const SizedBox(width: 5),
            Text(
              '$streak',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: isDark ? scheme.onSurface : BlueprintPalette.b700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
