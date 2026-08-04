import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

/// One exam mode in the selector — `.cbt-mode-card`.
class ModeCard extends StatelessWidget {
  const ModeCard({
    super.key,
    required this.icon,
    required this.name,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String name;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Tokens.rMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.rMd),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: Tokens.s3,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 21,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.3,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The grid the mode cards sit in — `.cbt-mode-grid`.
class ModeGrid extends StatelessWidget {
  const ModeGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        crossAxisCount: 2,
        mainAxisSpacing: Tokens.s2,
        crossAxisSpacing: Tokens.s2,
        // Wide and short: the description is two lines at most, and taller cards
        // would push the Start button below the fold on a small phone.
        childAspectRatio: 1.55,
        children: children,
      );
}
