import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/chat.dart';
import '../../core/theme/app_palette.dart';
import '../../core/toast.dart';

/// Renders whatever a message is carrying.
///
/// Port of the web's `FileRenderer`: a picture inline, a video with a play
/// affordance, an audio player for voice notes, and a download row for anything
/// else. The categories and field names match, so an attachment sent from either
/// side renders on both.
class MessageAttachment extends StatelessWidget {
  const MessageAttachment({
    super.key,
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final url = message.mediaUrl;
    if (url == null) return const SizedBox.shrink();

    return switch (message.mediaCategory) {
      MediaCategory.image => _ImageAttachment(url: url),
      MediaCategory.video => _VideoAttachment(url: url, message: message),
      MediaCategory.audio => VoiceNotePlayer(url: url, isMine: isMine),
      MediaCategory.document =>
        _DocumentAttachment(message: message, isMine: isMine),
    };
  }
}

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(Tokens.rSm),
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => _ImageViewer(url: url)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : SizedBox(
                      height: 160,
                      width: 200,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: progress.expectedTotalBytes == null
                              ? null
                              : progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!,
                        ),
                      ),
                    ),
              errorBuilder: (context, _, _) => const SizedBox(
                height: 120,
                width: 200,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
      );
}

/// Full-screen, pinch-to-zoom.
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              onPressed: () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              tooltip: 'Open',
            ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      );
}

/// A video is handed to the platform player rather than embedded.
///
/// Embedding one would mean a decoder per bubble in a scrolling list, which is
/// what makes a chat stutter on the mid-range phones this app targets.
class _VideoAttachment extends StatelessWidget {
  const _VideoAttachment({required this.url, required this.message});

  final String url;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ),
        borderRadius: BorderRadius.circular(Tokens.rSm),
        child: Container(
          width: 210,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(Tokens.rSm),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.play_circle_fill_rounded,
                size: 40,
                color: Colors.white,
              ),
              const SizedBox(height: 6),
              Text(
                message.readableSize ?? 'Video',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
      );
}

class _DocumentAttachment extends StatelessWidget {
  const _DocumentAttachment({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  static IconData _iconFor(String? mimeType) {
    final mime = (mimeType ?? '').toLowerCase();
    if (mime.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (mime.contains('word') || mime.contains('document')) {
      return Icons.description_rounded;
    }
    if (mime.contains('sheet') || mime.contains('excel')) {
      return Icons.table_chart_rounded;
    }
    if (mime.contains('presentation') || mime.contains('powerpoint')) {
      return Icons.slideshow_rounded;
    }
    if (mime.contains('zip') || mime.contains('compressed')) {
      return Icons.folder_zip_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = isMine ? scheme.onPrimary : scheme.onSurface;

    return InkWell(
      onTap: () async {
        final url = message.mediaUrl;
        if (url == null) return;
        final opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          showToast('No app can open this file.', variant: ToastVariant.error);
        }
      },
      borderRadius: BorderRadius.circular(Tokens.rSm),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Tokens.rSm),
        ),
        child: Row(
          children: [
            Icon(_iconFor(message.fileType), size: 26, color: foreground),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.fileName ?? 'File',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (message.readableSize != null)
                    Text(
                      message.readableSize!,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: foreground.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.download_rounded,
              size: 17,
              color: foreground.withValues(alpha: 0.8),
            ),
          ],
        ),
      ),
    );
  }
}

/// A voice note, with a scrub bar and a running time.
///
/// The website hands audio to the browser's native `<audio controls>`; a phone
/// has no such control, so this is the equivalent built out — play/pause, a
/// draggable position and the elapsed time against the total.
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({super.key, required this.url, required this.isMine});

  final String url;
  final bool isMine;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  final _player = AudioPlayer();
  final _subscriptions = <StreamSubscription<dynamic>>[];

  Duration _position = Duration.zero;
  Duration? _total;
  bool _playing = false;

  /// True while the student is dragging, so incoming position events don't fight
  /// the thumb out from under their finger.
  bool _scrubbing = false;

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _player.onDurationChanged.listen((duration) {
        if (mounted) setState(() => _total = duration);
      }),
      _player.onPositionChanged.listen((position) {
        if (mounted && !_scrubbing) setState(() => _position = position);
      }),
      _player.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() => _playing = state == PlayerState.playing);
        }
      }),
      _player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _playing = false;
            _position = Duration.zero;
          });
        }
      }),
    ]);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.play(UrlSource(widget.url));
      }
    } catch (_) {
      if (mounted) {
        showToast('Could not play this note.', variant: ToastVariant.error);
      }
    }
  }

  static String _clock(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = widget.isMine ? scheme.onPrimary : scheme.onSurface;
    final total = _total ?? Duration.zero;
    final maxMs = total.inMilliseconds.toDouble();

    return SizedBox(
      width: 218,
      child: Row(
        children: [
          InkWell(
            onTap: _toggle,
            customBorder: const CircleBorder(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 21,
                color: foreground,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: foreground,
                    inactiveTrackColor: foreground.withValues(alpha: 0.28),
                    thumbColor: foreground,
                  ),
                  child: Slider(
                    value: maxMs == 0
                        ? 0
                        : _position.inMilliseconds
                            .toDouble()
                            .clamp(0, maxMs),
                    max: maxMs == 0 ? 1 : maxMs,
                    onChangeStart: (_) => _scrubbing = true,
                    onChanged: maxMs == 0
                        ? null
                        : (value) => setState(
                              () => _position =
                                  Duration(milliseconds: value.round()),
                            ),
                    onChangeEnd: maxMs == 0
                        ? null
                        : (value) async {
                            await _player
                                .seek(Duration(milliseconds: value.round()));
                            _scrubbing = false;
                          },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.mic_rounded,
                        size: 11,
                        color: foreground.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        total == Duration.zero
                            ? _clock(_position)
                            : '${_clock(_position)} / ${_clock(total)}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: foreground.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
