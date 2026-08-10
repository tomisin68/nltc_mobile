import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Five tappable stars.
///
/// Shared by the Settings review card and the post-result prompt so a review
/// looks like the same act wherever the student is asked for one. Passing a
/// null [onRate] makes it a read-only display of [rating].
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.rating,
    required this.onRate,
    this.size = 28,
  });

  final int rating;
  final ValueChanged<int>? onRate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final interactive = onRate != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var n = 1; n <= 5; n++)
          IconButton(
            onPressed: interactive ? () => onRate!(n) : null,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            // Keeps every star a comfortable tap target even at small sizes —
            // a mis-tap here records the wrong opinion, not just a wrong tap.
            constraints: BoxConstraints(
              minWidth: size + 10,
              minHeight: size + 10,
            ),
            iconSize: size,
            tooltip: interactive ? '$n star${n > 1 ? 's' : ''}' : null,
            icon: Icon(
              n <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
              color: n <= rating
                  ? BlueprintPalette.warning
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
      ],
    );
  }
}
