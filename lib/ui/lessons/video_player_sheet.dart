import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../domain/models/lesson_video.dart';
import '../core/theme/app_palette.dart';

/// Full-screen lesson player.
///
/// Port of `VideoPlayer` inside `src/pages/dashboard/VideoLessonsView.jsx`. Two
/// paths, as on the web: a YouTube link plays through the IFrame player, anything
/// else through the platform video player with the same hand-built controls —
/// scrub bar, ±10s, play/pause and a speed cycle.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.video});

  final LessonVideo video;

  static Future<void> open(BuildContext context, LessonVideo video) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => VideoPlayerScreen(video: video),
        ),
      );

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  VideoPlayerController? _video;
  YoutubePlayerController? _youTube;
  String? _error;
  int _speedIndex = 2; // 1×

  @override
  void initState() {
    super.initState();
    final ytId = widget.video.youTubeId;
    if (ytId != null) {
      _youTube = YoutubePlayerController.fromVideoId(
        videoId: ytId,
        autoPlay: true,
        // Related videos are kept to the same channel: a student who finishes a
        // lesson should not be handed the rest of YouTube.
        params: const YoutubePlayerParams(strictRelatedVideos: true),
      );
    } else {
      _initDirect();
    }
  }

  Future<void> _initDirect() async {
    final url = widget.video.url;
    if (url == null || url.isEmpty) {
      setState(() => _error = 'This lesson has no video attached yet.');
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _video = controller);
      await controller.play();
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(
        () => _error = 'This lesson could not be played. Check your '
            'connection, or tell your tutor the link may be broken.',
      );
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    // The iframe controller closes asynchronously; nothing here waits on it, and
    // the widget is going away regardless.
    _youTube?.close();
    super.dispose();
  }

  void _seek(int seconds) {
    final controller = _video;
    if (controller == null) return;
    final target = controller.value.position + Duration(seconds: seconds);
    // Clamped at both ends: seeking past the end restarts on some platforms.
    controller.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > controller.value.duration
              ? controller.value.duration
              : target,
    );
  }

  void _cycleSpeed() {
    final controller = _video;
    if (controller == null) return;
    setState(() => _speedIndex = (_speedIndex + 1) % _speeds.length);
    controller.setPlaybackSpeed(_speeds[_speedIndex]);
  }

  @override
  Widget build(BuildContext context) {
    // The player is dark regardless of theme — it is a cinema, and the web's
    // `.video-player-box` is black in both.
    return Scaffold(
      backgroundColor: BlueprintPalette.ink,
      appBar: AppBar(
        backgroundColor: BlueprintPalette.ink,
        foregroundColor: BlueprintPalette.white,
        elevation: 0,
        title: Text(
          widget.video.title,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: BlueprintPalette.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(Tokens.s6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_rounded,
              size: 44,
              color: BlueprintPalette.b300,
            ),
            const SizedBox(height: Tokens.s4),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: BlueprintPalette.b200,
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }

    final youTube = _youTube;
    if (youTube != null) {
      // The package ships YouTube-styled controls of its own, themed to the
      // brand blue rather than YouTube red.
      return Theme(
        data: Theme.of(context).copyWith(
          extensions: const [
            YoutubePlayerTheme(progressBarActiveColor: BlueprintPalette.b500),
          ],
        ),
        child: YoutubePlayer(controller: youTube),
      );
    }

    final controller = _video;
    if (controller == null) {
      return const CircularProgressIndicator(color: BlueprintPalette.b400);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
        _Controls(
          controller: controller,
          speed: _speeds[_speedIndex],
          onSeek: _seek,
          onCycleSpeed: _cycleSpeed,
        ),
      ],
    );
  }
}

/// `.vp-controls` — scrub bar over a row of buttons.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.speed,
    required this.onSeek,
    required this.onCycleSpeed,
  });

  final VideoPlayerController controller;
  final double speed;
  final void Function(int) onSeek;
  final VoidCallback onCycleSpeed;

  @override
  Widget build(BuildContext context) => Container(
        color: BlueprintPalette.white.withValues(alpha: 0.06),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final total = value.duration.inMilliseconds;
            final progress = total == 0
                ? 0.0
                : (value.position.inMilliseconds / total).clamp(0.0, 1.0);

            return Column(
              children: [
                // Tappable scrub bar, matching `.vp-progress`'s click-to-seek.
                LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    onTapDown: (details) => controller.seekTo(
                      Duration(
                        milliseconds:
                            (details.localPosition.dx / constraints.maxWidth * total)
                                .round(),
                      ),
                    ),
                    child: Container(
                      height: 18,
                      alignment: Alignment.center,
                      // Transparent hit area so the 4px bar is still easy to hit.
                      color: Colors.transparent,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          height: 4,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ColoredBox(
                                  color: BlueprintPalette.white
                                      .withValues(alpha: 0.15),
                                ),
                              ),
                              Positioned.fill(
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress,
                                  child: const ColoredBox(
                                    color: BlueprintPalette.b500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _PlayerButton(
                      icon: Icons.replay_10_rounded,
                      onTap: () => onSeek(-10),
                    ),
                    const SizedBox(width: Tokens.s2),
                    _PlayerButton(
                      icon: value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onTap: () =>
                          value.isPlaying ? controller.pause() : controller.play(),
                    ),
                    const SizedBox(width: Tokens.s2),
                    _PlayerButton(
                      icon: Icons.forward_10_rounded,
                      onTap: () => onSeek(10),
                    ),
                    const Spacer(),
                    _PlayerButton(label: '${_trim(speed)}×', onTap: onCycleSpeed),
                    const SizedBox(width: Tokens.s2),
                    Text(
                      '${_clock(value.position)} / ${_clock(value.duration)}',
                      style: TextStyle(
                        color: BlueprintPalette.white.withValues(alpha: 0.8),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

  /// `1×` rather than `1.0×`, but `0.75×` keeps its decimals.
  static String _trim(double speed) =>
      speed == speed.roundToDouble() ? '${speed.round()}' : '$speed';

  static String _clock(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PlayerButton extends StatelessWidget {
  const _PlayerButton({this.icon, this.label, required this.onTap});

  final IconData? icon;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: BlueprintPalette.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Tokens.rXs),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.rXs),
          child: Container(
            constraints: const BoxConstraints(
              minWidth: Tokens.minTouchTarget,
              minHeight: 40,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: icon != null
                ? Icon(icon, size: 20, color: BlueprintPalette.white)
                : Text(
                    label!,
                    style: const TextStyle(
                      color: BlueprintPalette.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      );
}
