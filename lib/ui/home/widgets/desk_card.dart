import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_card.dart';

/// A numbered panel on the study desk.
///
/// Port of `.dh-card` / `.dh-hd`: a handwritten index number in Caveat, a
/// Fraunces title, and an optional pill or link at the trailing edge, over a
/// dashed rule. The numbers matter — they are what makes the dashboard read as
/// one worked-through page rather than a pile of unrelated widgets, and they run
/// in the same order as the website's.
class DeskCard extends StatelessWidget {
  const DeskCard({
    super.key,
    required this.number,
    required this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(Tokens.s4),
    this.footer,
  });

  /// Shown as written in the margin — `01`, `02`. Pass it zero-padded.
  final String number;
  final String title;

  /// A pill, a count, or a text link.
  final Widget? trailing;

  final Widget child;
  final EdgeInsets padding;

  /// The dashed-off note under the body — "Resets daily", and the like.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Tokens.s4, 13, Tokens.s4, 11),
            child: Row(
              children: [
                Text(
                  number,
                  style: GoogleFonts.caveat(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: BlueprintPalette.b400,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.fraunces(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.15,
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          DashedRule(color: scheme.outlineVariant),
          Padding(padding: padding, child: child),
          if (footer != null) ...[
            DashedRule(color: scheme.outlineVariant),
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.s4,
                vertical: Tokens.s2,
              ),
              child: footer,
            ),
          ],
        ],
      ),
    );
  }
}

/// `.dh-hd-pill` — the small count badge in a card header.
class DeskPill extends StatelessWidget {
  const DeskPill({super.key, required this.label, this.icon, this.tone});

  final String label;
  final IconData? icon;

  /// Overrides the default blue. Used for "Goal met 🎉".
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = tone ?? (isDark ? scheme.onPrimaryContainer : BlueprintPalette.b700);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? scheme.primaryContainer.withValues(alpha: 0.5)
            : BlueprintPalette.b100,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: isDark ? scheme.outlineVariant : BlueprintPalette.b200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: accent),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// `.dh-link-btn` — the "Full history →" style action in a card header or foot.
class DeskLink extends StatelessWidget {
  const DeskLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.rXs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 5),
            Icon(Icons.arrow_forward_rounded, size: 11, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// A card body that is still loading.
class DeskCardSpinner extends StatelessWidget {
  const DeskCardSpinner({super.key, this.height = 60});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
}

/// `.dh-nb-empty` — the "nothing here yet" state inside a desk card.
class DeskCardEmpty extends StatelessWidget {
  const DeskCardEmpty({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s5),
      child: Column(
        children: [
          Icon(icon, size: 28, color: BlueprintPalette.b300),
          const SizedBox(height: Tokens.s2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
