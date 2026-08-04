import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/video_repository.dart';
import '../../data/services/mission_signals.dart';
import '../../domain/models/access_state.dart';
import '../../domain/models/lesson_video.dart';
import '../core/state/session_controller.dart';
import '../core/state/xp_service.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/filter_bar.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/skeleton.dart';
import 'video_player_sheet.dart';

/// The lesson library.
///
/// Port of `src/pages/dashboard/VideoLessonsView.jsx`: search plus subject and
/// access filters over a card grid, padlocks on anything the account can't reach,
/// and XP the first time a lesson is opened.
class LessonsScreen extends StatefulWidget {
  const LessonsScreen({super.key});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  String _search = '';
  String? _subject;
  String? _access;

  /// Lessons already credited this session. The backend is idempotent per video,
  /// but this saves a needless round trip when a student reopens one.
  final _awarded = <String>{};

  Future<void> _play(LessonVideo video) async {
    final session = context.read<SessionController>();

    // Re-read the grant on the tap rather than trusting the last build: this grid
    // can sit on screen across the end of a trial, and a stale render must not
    // open a Pro lesson afterwards.
    if (video.isPro && !AccessState.evaluate(session.profile).active) {
      showToast('Upgrade to access this lesson', variant: ToastVariant.info);
      return;
    }

    if (_awarded.add(video.id)) {
      final uid = session.account?.uid;
      // Fire and forget — the lesson opens now, the XP toast lands when it lands.
      context.read<XpService>().award(
        'watch_lesson',
        meta: {'videoId': video.id},
      );
      context.read<MissionSignals>().set('watch_video', uid);
    }

    await VideoPlayerScreen.open(context, video);
  }

  @override
  Widget build(BuildContext context) {
    final access = context.select<SessionController, AccessState>(
      (s) => s.access,
    );

    return StreamBuilder<List<LessonVideo>>(
      stream: context.read<VideoRepository>().watch(),
      builder: (context, snapshot) {
        final videos = snapshot.data;
        final loading = videos == null && !snapshot.hasError;
        final all = videos ?? const <LessonVideo>[];

        final subjects = {
          for (final v in all)
            if (v.subject != null) v.subject!,
        }.toList()
          ..sort();

        final needle = _search.toLowerCase();
        final filtered = all.where((v) {
          if (_subject != null && v.subject != _subject) return false;
          if (_access != null && v.access != _access) return false;
          if (needle.isEmpty) return true;
          return v.title.toLowerCase().contains(needle) ||
              (v.subject?.toLowerCase().contains(needle) ?? false);
        }).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            Tokens.s4,
            0,
            Tokens.s4,
            Tokens.s10,
          ),
          children: [
            const PageHeader(
              title: 'Video Lessons',
              subtitle: 'Learn at your own pace with curated exam content.',
            ),
            FilterBar(
              search: FilterSearchField(
                hintText: 'Search lessons…',
                onChanged: (value) => setState(() => _search = value),
              ),
              filters: [
                FilterDropdown<String>(
                  value: _subject,
                  allLabel: 'All Subjects',
                  options: subjects,
                  labelOf: (s) => s,
                  onChanged: (value) => setState(() => _subject = value),
                ),
                FilterDropdown<String>(
                  value: _access,
                  allLabel: 'All Access',
                  options: const ['free', 'pro'],
                  labelOf: (a) => a == 'pro' ? 'Pro' : 'Free',
                  onChanged: (value) => setState(() => _access = value),
                ),
              ],
            ),
            if (loading)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: _gridDelegate,
                itemCount: 4,
                itemBuilder: (_, _) => const SkeletonVideoCard(),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Tokens.s6),
                child: EmptyState(
                  icon: Icons.movie_outlined,
                  title: all.isEmpty ? 'No lessons yet' : 'No lessons found',
                  message: all.isEmpty
                      ? 'Your tutors have not uploaded any lessons yet — check '
                          'back soon.'
                      : 'Try adjusting your filters or check back soon.',
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: _gridDelegate,
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final video = filtered[i];
                  return _VideoCard(
                    video: video,
                    // Free lessons are open to everyone; the rest need a live
                    // grant, which includes a running trial.
                    accessible: !video.isPro || access.active,
                    onTap: () => _play(video),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  /// The web's grid is `minmax(240px, 1fr)`. On a phone that is one column, which
  /// wastes the screen — 178px gives two, with the 16:9 thumbnail still legible.
  static const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 178,
    mainAxisSpacing: Tokens.s3,
    crossAxisSpacing: Tokens.s3,
    childAspectRatio: 0.78,
  );
}

/// `.video-card`
class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.video,
    required this.accessible,
    required this.onTap,
  });

  final LessonVideo video;
  final bool accessible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: accessible ? 1 : 0.75,
      child: Material(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.rMd),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.rMd),
              border: Border.all(color: scheme.outlineVariant),
            ),
            // `.video-card` insets its thumbnail on three sides, like a photo
            // mounted on a card.
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumbnail(video: video, locked: !accessible),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                            color: scheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          [
                            video.subject,
                            video.duration,
                          ].where((s) => s != null && s.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.video, required this.locked});

  final LessonVideo video;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // YouTube serves a thumbnail for free, so a lesson with no explicit one still
    // gets a picture rather than a placeholder.
    final ytId = video.youTubeId;
    final thumbnail = video.thumbnail ??
        (ytId == null ? null : 'https://i.ytimg.com/vi/$ytId/hqdefault.jpg');

    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnail != null)
              Image.network(
                thumbnail,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(scheme),
              )
            else
              _placeholder(scheme),
            if (locked)
              ColoredBox(
                color: BlueprintPalette.text1.withValues(alpha: 0.55),
                child: const Center(
                  child: Icon(
                    Icons.lock_rounded,
                    size: 22,
                    color: BlueprintPalette.white,
                  ),
                ),
              ),
            // `.video-access-badge`
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: video.isPro
                      ? BlueprintPalette.b100
                      : BlueprintPalette.successBg,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      video.isPro
                          ? Icons.local_fire_department_rounded
                          : Icons.check_rounded,
                      size: 9,
                      color: video.isPro
                          ? BlueprintPalette.b700
                          : const Color(0xFF059669),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      video.isPro ? 'Pro' : 'Free',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: video.isPro
                            ? BlueprintPalette.b700
                            : const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) => ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: Center(
          child: Icon(
            Icons.play_circle_outline_rounded,
            size: 30,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
}
