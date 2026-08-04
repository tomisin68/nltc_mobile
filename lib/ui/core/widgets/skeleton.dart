import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Shimmering placeholder block. Port of `.skeleton` in `globals.css`.
///
/// Used instead of a spinner wherever the shape of what's loading is known —
/// a list of lessons that fades into place reads as faster than the same list
/// behind a spinner, even when it isn't.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
  });

  const Skeleton.circle({super.key, required double size})
      : width = size,
        height = size,
        borderRadius = null,
        shape = BoxShape.circle;

  final double? width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHigh;
    final highlight = Theme.of(context).brightness == Brightness.dark
        ? scheme.surfaceContainerHighest
        : BlueprintPalette.b200;

    // A still block when the OS asks for reduced motion — it carries the same
    // "content is coming" meaning without the sweep.
    if (MediaQuery.disableAnimationsOf(context)) {
      return _box(base, base, 0, scheme);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          _box(base, highlight, _controller.value, scheme),
    );
  }

  Widget _box(Color base, Color highlight, double t, ColorScheme scheme) {
    // Sweeps left to right across twice the width, so the band spends time off
    // both edges rather than snapping.
    final begin = Alignment(-1 - 2 + t * 4, 0);
    final end = Alignment(1 - 2 + t * 4, 0);

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        shape: widget.shape,
        borderRadius: widget.shape == BoxShape.circle
            ? null
            : (widget.borderRadius ?? BorderRadius.circular(Tokens.rXs)),
        gradient: LinearGradient(
          begin: begin,
          end: end,
          colors: [base, highlight, base],
        ),
      ),
    );
  }
}

/// `SkeletonListItem` — a row of text lines, for lists of cards.
class SkeletonListItem extends StatelessWidget {
  const SkeletonListItem({super.key, this.lines = 2, this.showAvatar = true});

  final int lines;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showAvatar) ...[
              const Skeleton.circle(size: 38),
              const SizedBox(width: Tokens.s3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines; i++) ...[
                    if (i > 0) const SizedBox(height: Tokens.s2),
                    // Later lines are shorter, the way real copy runs out.
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: i == 0 ? 0.62 : 0.9 - i * 0.15,
                      child: Skeleton(height: i == 0 ? 14 : 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

/// `SkeletonVideoCard` — a thumbnail with a title beneath it.
class SkeletonVideoCard extends StatelessWidget {
  const SkeletonVideoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AspectRatio(
            aspectRatio: 16 / 9,
            child: Skeleton(height: double.infinity, borderRadius: BorderRadius.zero),
          ),
          Padding(
            padding: const EdgeInsets.all(Tokens.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Skeleton(height: 13),
                const SizedBox(height: Tokens.s2),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.5,
                  child: const Skeleton(height: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `SkeletonTable` — stand-in for the data tables (history, honour roll).
class SkeletonTable extends StatelessWidget {
  const SkeletonTable({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Tokens.s4),
        child: Column(
          children: [
            for (var i = 0; i < rows; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              Row(
                children: [
                  const Skeleton(width: 26, height: 12),
                  const SizedBox(width: Tokens.s3),
                  const Skeleton.circle(size: 30),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(child: Skeleton(height: 12)),
                  const SizedBox(width: Tokens.s3),
                  const Skeleton(width: 48, height: 12),
                ],
              ),
            ],
          ],
        ),
      );
}
