import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// The NLTC logo lockup — a gradient tile plus the wordmark.
///
/// Colours come from the scheme rather than the raw palette so the mark stays
/// legible in dark mode instead of sitting as a bright slab on a navy surface.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56, this.showWordmark = true});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.secondary],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        'N',
        style: TextStyle(
          color: scheme.onPrimary,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );

    if (!showWordmark) return Semantics(label: 'NLTC', child: tile);

    return Semantics(
      label: 'NLTC Online',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tile,
          const SizedBox(width: Tokens.s3),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NLTC',
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'Online',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 3.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
