import 'package:flutter/material.dart';

import '../../../domain/models/subject.dart';
import '../theme/app_palette.dart';

/// The grid of subject tiles shared by CBT Practice, BECE Practice and Study
/// Notes.
///
/// Port of `.cbt-subj-grid` / `.quick-cbt-card`. The web uses `auto-fill` with a
/// minimum track; the phone equivalent is a fixed extent so tiles stay legible
/// rather than collapsing to two-per-row on a small screen.
class SubjectGrid extends StatelessWidget {
  const SubjectGrid({
    super.key,
    required this.subjects,
    required this.onTap,
    required this.caption,
  });

  final List<Subject> subjects;
  final void Function(Subject) onTap;

  /// The small label under each subject name — "Study", "Notes", …
  final String caption;

  @override
  Widget build(BuildContext context) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SixedCrossAxisDelegate(),
        itemCount: subjects.length,
        itemBuilder: (context, i) => SubjectTile(
          subject: subjects[i],
          caption: caption,
          onTap: () => onTap(subjects[i]),
        ),
      );
}

/// Tiles about 112px wide, which fits three across a typical handset and four on
/// a larger one without ever squeezing a subject name past two lines.
class SixedCrossAxisDelegate extends SliverGridDelegateWithMaxCrossAxisExtent {
  const SixedCrossAxisDelegate()
      : super(
          maxCrossAxisExtent: 132,
          mainAxisSpacing: Tokens.s2,
          crossAxisSpacing: Tokens.s2,
          childAspectRatio: 0.95,
        );
}

/// `.quick-cbt-card` — one subject.
class SubjectTile extends StatelessWidget {
  const SubjectTile({
    super.key,
    required this.subject,
    required this.caption,
    required this.onTap,
  });

  final Subject subject;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Tokens.rMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.rMd),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s2,
            vertical: Tokens.s3,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(subject.icon, size: 22, color: subject.color),
              const SizedBox(height: 6),
              Text(
                subject.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
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
