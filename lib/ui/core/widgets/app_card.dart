import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_palette.dart';

/// The panel every view builds out of.
///
/// Port of `.card` / `.card-header` / `.card-body` in `globals.css`. The header's
/// dashed rule is the detail that ties it to the exercise-book sidebar, so it is
/// drawn rather than left as a plain divider.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.title,
    this.titleIcon,
    this.headerTrailing,
    this.child,
    this.padding = const EdgeInsets.all(Tokens.s4),
    this.onTap,
  });

  /// When set, the card gets a header row.
  final String? title;
  final IconData? titleIcon;

  /// Sits at the trailing edge of the header — a count, or a text action.
  final Widget? headerTrailing;

  final Widget? child;

  /// Padding around [child]. Pass `EdgeInsets.zero` for a card whose body is a
  /// full-bleed list.
  final EdgeInsets padding;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              14,
              Tokens.s4,
              14,
            ),
            child: Row(
              children: [
                if (titleIcon != null) ...[
                  Icon(titleIcon, size: 14, color: scheme.primary),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: GoogleFonts.fraunces(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                ?headerTrailing,
              ],
            ),
          ),
          DashedRule(color: scheme.outlineVariant),
        ],
        if (child != null) Padding(padding: padding, child: child),
      ],
    );

    final card = Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Tokens.rLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rLg),
        child: card,
      ),
    );
  }
}

/// A dashed hairline — the `1px dashed` separators the design leans on.
class DashedRule extends StatelessWidget {
  const DashedRule({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(double.infinity, 1),
        painter: _DashedRulePainter(color),
      );
}

class _DashedRulePainter extends CustomPainter {
  const _DashedRulePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 3.0;
    const gap = 3.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRulePainter old) => old.color != color;
}

/// `.card-action` — the small text button in a card header.
class CardAction extends StatelessWidget {
  const CardAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

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
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 11, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// `.badge` — the uppercase pill used for exam types, plans and statuses.
enum BadgeTone { navy, gold, teal, success, error }

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = BadgeTone.navy,
    this.icon,
  });

  final String label;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (background, foreground) = switch (tone) {
      BadgeTone.success => (
          isDark ? scheme.tertiaryContainer : BlueprintPalette.successBg,
          isDark ? scheme.onTertiaryContainer : const Color(0xFF059669),
        ),
      BadgeTone.error => (
          isDark ? scheme.errorContainer : BlueprintPalette.errorBg,
          isDark ? scheme.onErrorContainer : const Color(0xFFDC2626),
        ),
      BadgeTone.gold => (
          isDark ? scheme.primaryContainer : BlueprintPalette.b100,
          isDark ? scheme.onPrimaryContainer : BlueprintPalette.b700,
        ),
      // The web's `.badge-teal` reads as a lighter blue in the Blueprint remap.
      BadgeTone.teal => (
          isDark ? scheme.surfaceContainerHigh : BlueprintPalette.b50,
          isDark ? scheme.onSurface : BlueprintPalette.b600,
        ),
      BadgeTone.navy => (
          isDark
              ? scheme.surfaceContainerHigh
              : const Color(0x0F092A5E), // rgba(9,42,94,.06)
          isDark ? scheme.onSurfaceVariant : BlueprintPalette.b800,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 9, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              height: 1.4,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
