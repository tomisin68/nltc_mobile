import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/subject_repository.dart';
import '../../data/repositories/video_repository.dart';
import '../../data/services/mission_signals.dart';
import '../../domain/models/access_state.dart';
import '../../domain/models/lesson_video.dart';
import '../../domain/models/subject.dart';
import '../core/state/session_controller.dart';
import '../core/state/xp_service.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/filter_bar.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/skeleton.dart';
import '../core/widgets/subject_grid.dart';
import '../shell/dashboard_sidebar.dart' show DashboardSidebar;
import 'video_player_sheet.dart';

/// The lesson library — class → subject → topic → lessons.
///
/// Port of `src/pages/dashboard/VideoLessonsView.jsx`. A senior student walks
/// down their own shelf: SSS 1–3, Practicals or UTME, then a subject, then a
/// topic, landing on the lessons filed under it — several per topic, each from a
/// different YouTube expert. The search box shortcuts the walk and matches
/// topics anywhere in the library.
///
/// Every list on the way down is built from the lessons that exist, so a student
/// never taps into an empty room: only subjects we have filmed appear, and only
/// their stocked topics.
///
/// Junior (BECE/JSS) students keep the flat grid: the class shelves are a senior
/// syllabus idea, and there are no JSS-tagged lessons to hang off them. Padlocks
/// and the XP award on first play work the same at every level.
class LessonsScreen extends StatefulWidget {
  const LessonsScreen({super.key});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  String _search = '';

  // Where the student is in the walk. Null all the way down = the class grid.
  ClassLevel? _class;
  Subject? _subject;

  /// The topic name, not the shelf: the library is a live snapshot, so a lesson
  /// published while a student sits on a topic should appear under them.
  String? _topicName;

  /// The senior pick-list, which orders the subject grid. Empty until the first
  /// read lands — the grid shows a skeleton until then.
  List<Subject> _subjects = const [];

  /// Lessons already credited this session. The backend is idempotent per video,
  /// but this saves a needless round trip when a student reopens one.
  final _awarded = <String>{};

  bool get _isJunior =>
      DashboardSidebar.isJuniorStudent(context.read<SessionController>().profile);

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    final subjects = await context.read<SubjectRepository>().decorated(
      SubjectCategory.senior,
    );
    if (!mounted) return;
    setState(() => _subjects = subjects);
  }

  void _openSubject(Subject subject) => setState(() {
        _subject = subject;
        _topicName = null;
      });

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

        return _body(all, loading: loading, access: access);
      },
    );
  }

  Widget _body(
    List<LessonVideo> all, {
    required bool loading,
    required AccessState access,
  }) {
    final searching = _search.trim().isNotEmpty;

    if (_isJunior) {
      return _page([
        const PageHeader(
          title: 'Video Lessons',
          subtitle: 'Learn at your own pace with curated exam content.',
        ),
        _searchBar(),
        ..._grid(
          searching ? all.where((v) => v.matchesSearch(_search)).toList() : all,
          loading: loading,
          access: access,
        ),
      ]);
    }

    // Search short-circuits every level of the walk. It spans the chosen class
    // so a hit is always something the student can open from where they stand.
    if (searching) {
      final hits = all
          .where((v) => v.matchesClass(_class) && v.matchesSearch(_search))
          .toList();
      return _page([
        PageHeader(
          title: 'Video Lessons',
          subtitle: '${hits.length} lesson${hits.length == 1 ? '' : 's'} '
              'matching "${_search.trim()}"'
              '${_class == null ? '' : ' in ${_class!.label}'}.',
        ),
        _searchBar(),
        ..._grid(hits, loading: loading, access: access),
      ]);
    }

    if (_subject != null) {
      // Both remaining levels read the same shelves, so they are built once here
      // and re-derived on every snapshot rather than frozen at tap time.
      final forSubject = all
          .where((v) => v.matchesClass(_class) && v.subject == _subject!.name)
          .toList();
      final shelves = VideoRepository.buildShelves(forSubject);

      final wanted = _topicName;
      if (wanted != null) {
        return _lessonList(_shelfFor(shelves, wanted), access: access);
      }
      return _topicList(shelves, loading: loading);
    }
    if (_class != null) return _subjectGrid(all, loading: loading);
    return _classGrid(all, loading: loading);
  }

  /// The shelf a student opened, or an empty one if its last lesson has since
  /// been pulled — better a "coming soon" than being bounced up a level.
  static TopicShelf _shelfFor(List<TopicShelf> shelves, String topic) {
    final key = topic.toLowerCase().trim();
    return shelves.firstWhere(
      (s) => s.topic.toLowerCase().trim() == key,
      orElse: () => TopicShelf(topic: topic, videos: const []),
    );
  }

  ListView _page(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
        children: children,
      );

  Widget _searchBar() => FilterBar(
        search: FilterSearchField(
          hintText: 'Search by topic…',
          onChanged: (value) => setState(() => _search = value),
        ),
        filters: const [],
      );

  // ─── Level 1: the class shelves ──────────────────────────────────────────
  Widget _classGrid(List<LessonVideo> all, {required bool loading}) => _page([
        const PageHeader(
          title: 'Video Lessons',
          subtitle: 'Pick your class or track, then browse subject by subject '
              'and topic by topic.',
        ),
        _searchBar(),
        AppCard(
          // Five shelves no longer fit a row on a handset, so they wrap: the
          // three classes on the first line, the two tracks under them.
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: _classGridDelegate,
            itemCount: ClassLevel.values.length,
            itemBuilder: (context, i) {
              final level = ClassLevel.values[i];
              return _ClassTile(
                level: level,
                caption: loading
                    ? 'Loading…'
                    : _lessonCount(
                        all.where((v) => v.matchesClass(level)).length,
                      ),
                onTap: () => setState(() => _class = level),
              );
            },
          ),
        ),
      ]);

  // ─── Level 2: subjects within a class ────────────────────────────────────
  Widget _subjectGrid(List<LessonVideo> all, {required bool loading}) {
    final level = _class!;
    final counts = <String, int>{};
    for (final v in all) {
      if (v.matchesClass(level) && v.subject != null) {
        counts[v.subject!] = (counts[v.subject!] ?? 0) + 1;
      }
    }

    // Only the subjects we have actually filmed for this shelf. The pick-list
    // sets the order; a lesson filed under a subject that has since left it
    // still gets a tile at the end, rather than becoming unreachable.
    final listed = {for (final s in _subjects) s.name};
    final stocked = [
      ..._subjects.where((s) => counts.containsKey(s.name)),
      ...Subjects.decorate(
        counts.keys.where((name) => !listed.contains(name)).toList()..sort(),
      ),
    ];

    return _page([
      _BackLink(label: 'Classes', onTap: () => setState(() => _class = null)),
      PageHeader(
        title: level.label,
        subtitle: 'Pick a subject to browse its topics.',
        leading: Icon(level.icon, size: 20, color: level.color),
      ),
      _searchBar(),
      AppCard(
        child: loading || _subjects.isEmpty
            ? const SkeletonListItem(lines: 2)
            : stocked.isEmpty
                ? EmptyState(
                    icon: Icons.movie_outlined,
                    title: 'No lessons yet',
                    message: 'Nothing has been filmed for ${level.label} so far '
                        '— try another class, or check back soon.',
                  )
                : SubjectGrid(
                    subjects: stocked,
                    captionOf: (s) => _lessonCount(counts[s.name]!),
                    onTap: _openSubject,
                  ),
      ),
    ]);
  }

  // ─── Level 3: topics within a subject ────────────────────────────────────
  Widget _topicList(List<TopicShelf> shelves, {required bool loading}) {
    final scheme = Theme.of(context).colorScheme;
    final subject = _subject!;
    final level = _class!;

    return _page([
      _BackLink(
        label: 'Subjects',
        onTap: () => setState(() {
          _subject = null;
          _topicName = null;
        }),
      ),
      PageHeader(
        title: subject.name,
        subtitle: 'Pick a topic to watch its lessons · ${level.label}',
        leading: Icon(subject.icon, size: 20, color: subject.color),
      ),
      _searchBar(),
      if (loading)
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < 5; i++)
                const SkeletonListItem(lines: 1, showAvatar: false),
            ],
          ),
        )
      else if (shelves.isEmpty)
        // Only reachable if the last lesson under a subject is pulled while the
        // student is standing on it — the grid behind them never offers one.
        const AppCard(
          child: EmptyState(
            icon: Icons.movie_outlined,
            title: 'No lessons yet',
            message: 'Nothing has been filmed for this subject yet — check back '
                'soon.',
          ),
        )
      else
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < shelves.length; i++) ...[
                if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                _TopicRow(
                  shelf: shelves[i],
                  accent: subject.color,
                  onTap: () => setState(() => _topicName = shelves[i].topic),
                ),
              ],
            ],
          ),
        ),
    ]);
  }

  // ─── Level 4: the lessons under one topic ────────────────────────────────
  Widget _lessonList(TopicShelf shelf, {required AccessState access}) {
    final subject = _subject!;
    final level = _class!;
    final experts = shelf.expertCount;

    return _page([
      _BackLink(
        label: subject.name,
        onTap: () => setState(() => _topicName = null),
      ),
      PageHeader(
        title: shelf.topic,
        subtitle: [
          subject.name,
          level.label,
          if (shelf.hasVideos)
            '${_lessonCount(shelf.videos.length)}'
                '${experts > 1 ? ' from $experts experts' : ''}',
        ].join(' · '),
      ),
      _searchBar(),
      if (!shelf.hasVideos)
        const AppCard(
          child: EmptyState(
            icon: Icons.hourglass_empty_rounded,
            title: 'Lessons coming soon',
            message: 'No videos have been added for this topic yet — check back '
                'later.',
          ),
        )
      else
        ..._grid(shelf.videos, loading: false, access: access),
    ]);
  }

  /// The card grid, shared by the topic list, search results and the JSS view.
  List<Widget> _grid(
    List<LessonVideo> videos, {
    required bool loading,
    required AccessState access,
  }) {
    if (loading) {
      return [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: _gridDelegate,
          itemCount: 4,
          itemBuilder: (_, _) => const SkeletonVideoCard(),
        ),
      ];
    }
    if (videos.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.only(top: Tokens.s6),
          child: EmptyState(
            icon: Icons.movie_outlined,
            title: 'No lessons found',
            message: 'Try a different topic, or check back soon.',
          ),
        ),
      ];
    }
    return [
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: _gridDelegate,
        itemCount: videos.length,
        itemBuilder: (context, i) => _VideoCard(
          video: videos[i],
          // Free lessons are open to everyone; the rest need a live grant,
          // which includes a running trial.
          accessible: !videos[i].isPro || access.active,
          onTap: () => _play(videos[i]),
        ),
      ),
    ];
  }

  static String _lessonCount(int n) => '$n lesson${n == 1 ? '' : 's'}';

  /// The class tiles size like the subject tiles a level down, only taller: a
  /// two-line label such as "Practicals" has to clear the lesson count under it.
  static const _classGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 132,
    mainAxisSpacing: Tokens.s2,
    crossAxisSpacing: Tokens.s2,
    childAspectRatio: 0.86,
  );

  /// The web's grid is `minmax(240px, 1fr)`. On a phone that is one column, which
  /// wastes the screen — 178px gives two, with the 16:9 thumbnail still legible.
  static const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 178,
    mainAxisSpacing: Tokens.s3,
    crossAxisSpacing: Tokens.s3,
    childAspectRatio: 0.78,
  );
}

/// `.video-class-card` — one shelf: a class, or the Practicals/UTME track.
class _ClassTile extends StatelessWidget {
  const _ClassTile({
    required this.level,
    required this.caption,
    required this.onTap,
  });

  final ClassLevel level;
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
            // The web card wears its class colour as a top rule.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.02, 0.02],
              colors: [level.color, level.color, scheme.surfaceContainerLow],
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s2,
            vertical: Tokens.s3,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(level.icon, size: 24, color: level.color),
              const SizedBox(height: 6),
              Text(
                level.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

/// `.btn-outline.btn-xs` used as a breadcrumb back up one level.
class _BackLink extends StatelessWidget {
  const _BackLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.s3),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 15),
            label: Text(label),
          ),
        ),
      );
}

/// `.sched-row` — one stocked topic, with its subject-coloured spine and count.
class _TopicRow extends StatelessWidget {
  const _TopicRow({
    required this.shelf,
    required this.accent,
    required this.onTap,
  });

  final TopicShelf shelf;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = shelf.videos.length;

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Tokens.minTouchTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s4,
          vertical: Tokens.s3,
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 22,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Text(
                shelf.topic,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
            AppBadge(label: '$count video${count == 1 ? '' : 's'}'),
            const SizedBox(width: Tokens.s2),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
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
    // The expert is the point of the library — several takes on one topic — so
    // they get the meta line, falling back to the subject when unnamed.
    final meta = video.teacher ?? video.subject ?? '';

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
                        if (meta.isNotEmpty)
                          Row(
                            children: [
                              if (video.teacher != null) ...[
                                Icon(
                                  Icons.person_rounded,
                                  size: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 3),
                              ],
                              Expanded(
                                child: Text(
                                  meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
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
    final duration = video.duration;

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
            // `.video-duration-badge`
            if (duration != null && duration.isNotEmpty)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: BlueprintPalette.text1.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    duration,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: BlueprintPalette.white,
                    ),
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
