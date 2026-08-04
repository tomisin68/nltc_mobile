import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Draws the exercise-book ruling behind [child].
///
/// The design uses this `repeating-linear-gradient` in several places at
/// different line spacings — 44px in the sidebar, 36px on the honour-roll card,
/// 32px on a notice-board note. Painted rather than tiled from an asset so it
/// stays crisp at any density and follows the theme.
class RuledPaper extends StatelessWidget {
  const RuledPaper({
    super.key,
    required this.child,
    this.lineSpacing = 44,
    this.marginRuleAt,
  });

  final Widget child;

  /// Distance between rules, in logical pixels.
  final double lineSpacing;

  /// When set, also draws the vertical margin rule this far from the left edge —
  /// the sidebar's `::before`.
  final double? marginRuleAt;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: RuledPaperPainter(
          isDark: Theme.of(context).brightness == Brightness.dark,
          lineSpacing: lineSpacing,
          marginRuleAt: marginRuleAt,
        ),
        child: child,
      );
}

class RuledPaperPainter extends CustomPainter {
  const RuledPaperPainter({
    required this.isDark,
    this.lineSpacing = 44,
    this.marginRuleAt,
  });

  final bool isDark;
  final double lineSpacing;
  final double? marginRuleAt;

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()
      // The web uses .055 alpha on white; on the dark surface that would vanish,
      // so it is lifted just enough to still read as ruling rather than as lines.
      ..color = BlueprintPalette.b500.withValues(alpha: isDark ? 0.09 : 0.055)
      ..strokeWidth = 1;

    for (var y = lineSpacing - 1; y < size.height; y += lineSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }

    final marginX = marginRuleAt;
    if (marginX == null) return;

    final margin = Paint()
      ..color = BlueprintPalette.b500.withValues(alpha: isDark ? 0.26 : 0.16)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(marginX, 0), Offset(marginX, size.height), margin);
  }

  @override
  bool shouldRepaint(RuledPaperPainter old) =>
      old.isDark != isDark ||
      old.lineSpacing != lineSpacing ||
      old.marginRuleAt != marginRuleAt;
}
