import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_palette.dart';

/// The title block every dashboard view opens with.
///
/// Port of `.page-hdr` in `globals.css`: a Fraunces heading swept with a
/// highlighter mark, over a one-line description. The mark is drawn behind the
/// text rather than under it, which is what makes it read as highlighter on paper
/// instead of an underline.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.leading});

  final String title;
  final String? subtitle;

  /// A subject icon, when the header names one — Study Notes uses this.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final heading = Text(
      title,
      style: GoogleFonts.fraunces(
        fontSize: 21,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.6,
        height: 1.2,
        color: scheme.onSurface,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: Tokens.s2),
              ],
              // Shrink-wrapped so the highlighter stops at the end of the words,
              // not at the end of the row.
              Flexible(
                child: Stack(
                  children: [
                    Positioned(
                      left: -5,
                      right: -9,
                      bottom: 3,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.transparent,
                              BlueprintPalette.b500.withValues(alpha: 0.16),
                              BlueprintPalette.b500.withValues(alpha: 0.11),
                              Colors.transparent,
                            ],
                            stops: const [0.01, 0.04, 0.96, 0.99],
                          ),
                        ),
                      ),
                    ),
                    heading,
                  ],
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
