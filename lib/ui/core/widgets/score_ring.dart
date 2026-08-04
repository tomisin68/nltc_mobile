import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Circular score dial, from a muted red through amber to green.
///
/// The colour is scored, not decorative: a student should read the band before
/// they read the number. Thresholds match how the boards grade — 70+ is strong,
/// 50 is the pass line, below 40 needs work.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.percent,
    this.size = 132,
    this.strokeWidth = 12,
    this.animate = true,
    this.caption,
  });

  /// 0–100.
  final double percent;
  final double size;
  final double strokeWidth;
  final bool animate;
  final String? caption;

  static Color colorFor(double percent, ColorScheme scheme) {
    if (percent >= 70) return BlueprintPalette.success;
    if (percent >= 50) return scheme.primary;
    if (percent >= 40) return BlueprintPalette.warning;
    return scheme.error;
  }

  static String bandFor(double percent) {
    if (percent >= 80) return 'Excellent';
    if (percent >= 70) return 'Very good';
    if (percent >= 50) return 'Pass';
    if (percent >= 40) return 'Below par';
    return 'Needs work';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final value = (percent / 100).clamp(0.0, 1.0);
    final color = colorFor(percent, scheme);

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: animate ? 0 : value, end: value),
        duration: animate ? const Duration(milliseconds: 900) : Duration.zero,
        curve: Motion.emphasized,
        builder: (context, animated, _) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: animated,
                strokeWidth: strokeWidth,
                strokeCap: StrokeCap.round,
                backgroundColor: scheme.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(animated * 100).round()}%',
                  style: text.headlineMedium?.copyWith(
                    color: color,
                    fontSize: size * 0.24,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
