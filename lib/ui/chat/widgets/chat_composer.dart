import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/theme/app_palette.dart';
import '../../core/toast.dart';

/// A file the student has chosen but not yet sent.
class PendingAttachment {
  const PendingAttachment({
    required this.file,
    required this.fileName,
    required this.mimeType,
  });

  final File file;
  final String fileName;
  final String mimeType;
}

/// The message bar: text, attachments, and hold-to-record.
///
/// Recording is the app's own addition. The website retired its recorder (and
/// the storage rules block the old `voice-notes/` path), but audio *attachments*
/// are still first-class there — so a note recorded here is uploaded as a normal
/// chat file with an audio MIME type, which the website plays back as it always
/// has. Nothing about the data model had to change for it.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.sending,
    required this.onChanged,
    required this.onSend,
    required this.onAttach,
    required this.lockedNote,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  /// Called with whatever the student picked or recorded.
  final ValueChanged<PendingAttachment> onAttach;

  final String? lockedNote;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _recorder = AudioRecorder();

  bool _recording = false;

  /// True while [_startRecording] is waiting on permission or on the platform.
  ///
  /// The gap matters: asking for the microphone the first time puts a system
  /// dialog over the app, which takes the press away and used to leave the
  /// recorder starting with nothing left holding it.
  bool _starting = false;

  /// Set when the press ended before the recorder had actually started, so the
  /// start knows to stop again the moment it finishes.
  bool _abandoned = false;

  /// Bumped whenever a recording is thrown away outright.
  ///
  /// A recorder that was still opening when that happened would otherwise finish
  /// opening a moment later and quietly install itself over a screen that has
  /// already cancelled it.
  int _startToken = 0;

  /// True when the recording no longer depends on a finger being held down —
  /// either it was started with a tap, or it was slid up and locked. The bar's
  /// buttons are what finish it.
  bool _handsFree = false;

  /// How far the held finger has slid left, for the cancel hint.
  double _slid = 0;

  DateTime? _startedAt;
  Duration _recordedFor = Duration.zero;
  Timer? _recordTimer;
  String? _recordingPath;

  /// Below this a press reads as a mis-tap rather than a note.
  static const _minimumRecording = Duration(milliseconds: 900);

  /// A recording nobody stopped is stopped here. Long enough for any real note,
  /// short enough that a phone left in a pocket doesn't fill its storage.
  static const _maximumRecording = Duration(minutes: 5);

  /// How far the finger has to travel left before releasing cancels instead of
  /// sending, and how far up before the recording stops needing the finger.
  static const _cancelDistance = 90.0;
  static const _lockDistance = 60.0;

  @override
  void dispose() {
    _recordTimer?.cancel();
    // Whatever is on the microphone goes with the screen. `cancel` both stops
    // the recorder and drops the part-written file.
    if (_recording || _starting) unawaited(_recorder.cancel());
    _recorder.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChatComposer old) {
    super.didUpdateWidget(old);
    // The group was locked, or this student was removed from it, while they were
    // part-way through a note. There is nowhere to send it now.
    if (!widget.enabled && (_recording || _starting)) {
      unawaited(_discardRecording());
    }
  }

  // ─── Attachments ───────────────────────────────────────────────────────────

  Future<void> _openAttachmentMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_rounded),
              title: const Text('Photo'),
              onTap: () => Navigator.of(sheetContext).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_rounded),
              title: const Text('Video'),
              onTap: () => Navigator.of(sheetContext).pop('video'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: const Text('Document'),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case 'image':
        await _pickImage(ImageSource.gallery);
      case 'camera':
        await _pickImage(ImageSource.camera);
      case 'video':
        await _pickVideo();
      case 'file':
        await _pickDocument();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      // Full-resolution phone photos are several megabytes each and are being
      // looked at on a phone; this keeps a class group chat usable on data.
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null) return;
    _emit(picked.path, picked.name, _mimeFor(picked.name, 'image/jpeg'));
  }

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (picked == null) return;
    _emit(picked.path, picked.name, _mimeFor(picked.name, 'video/mp4'));
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles();
    final picked = result?.files.singleOrNull;
    final path = picked?.path;
    if (picked == null || path == null) return;
    _emit(path, picked.name, _mimeFor(picked.name, 'application/octet-stream'));
  }

  void _emit(String path, String name, String mimeType) => widget.onAttach(
        PendingAttachment(
          file: File(path),
          fileName: name,
          mimeType: mimeType,
        ),
      );

  static String _mimeFor(String name, String fallback) =>
      switch (name.toLowerCase().split('.').last) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'mp4' => 'video/mp4',
        'mov' => 'video/quicktime',
        'm4a' => 'audio/mp4',
        'mp3' => 'audio/mpeg',
        'aac' => 'audio/aac',
        'wav' => 'audio/wav',
        'pdf' => 'application/pdf',
        'doc' => 'application/msword',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls' => 'application/vnd.ms-excel',
        'xlsx' =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt' => 'application/vnd.ms-powerpoint',
        'pptx' =>
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'zip' => 'application/zip',
        'txt' => 'text/plain',
        _ => fallback,
      };

  // ─── Recording ─────────────────────────────────────────────────────────────

  /// Begins a note.
  ///
  /// [handsFree] is true when it was started by a tap rather than a hold, in
  /// which case nothing is waiting on a finger and the bar's own buttons finish
  /// it. Asking for the microphone can take the press away — the permission
  /// dialog is a window over the app — so a hold that has to ask ends up
  /// hands-free too, rather than starting a recording nothing is holding.
  Future<void> _startRecording({required bool handsFree}) async {
    if (_recording || _starting) return;

    final token = ++_startToken;
    setState(() {
      _starting = true;
      _abandoned = false;
      _handsFree = handsFree;
      _slid = 0;
    });

    var asked = false;
    try {
      // Checked without asking first, because asking is what puts a system
      // dialog over the app — and the dialog takes the press with it. Only when
      // the answer is no is the question actually put, and then the recording
      // stops depending on a finger that is no longer there.
      var granted = await _recorder.hasPermission(request: false);
      if (!granted) {
        asked = true;
        granted = await _recorder.hasPermission();
      }
      if (!granted) {
        if (!mounted || token != _startToken) return;
        setState(() => _starting = false);
        showToast(
          'NLTC needs microphone access to record a voice note.',
          variant: ToastVariant.error,
        );
        return;
      }
      if (token != _startToken) return;

      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/nltc_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        // AAC in an m4a container: what both mobile platforms record natively
        // and what every browser can play, so the note works on the website too.
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: path,
      );
      _recordingPath = path;
    } catch (_) {
      if (!mounted || token != _startToken) return;
      setState(() => _starting = false);
      showToast('Could not start recording.', variant: ToastVariant.error);
      return;
    }

    // Thrown away, or the screen went, while the microphone was opening.
    if (!mounted || token != _startToken) {
      unawaited(_recorder.cancel());
      await _deleteQuietly(File(_recordingPath ?? ''));
      _recordingPath = null;
      return;
    }

    setState(() {
      _starting = false;
      _recording = true;
      _startedAt = DateTime.now();
      _recordedFor = Duration.zero;
    });

    // Counted off the start time rather than accumulated a second at a time, so
    // a timer starved by a busy frame doesn't make the clock lie.
    _recordTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final started = _startedAt;
      if (started == null) return;
      final elapsed = DateTime.now().difference(started);
      if (elapsed >= _maximumRecording) {
        unawaited(_finishRecording(send: true));
        return;
      }
      if (elapsed.inSeconds != _recordedFor.inSeconds) {
        setState(() => _recordedFor = elapsed);
      }
    });

    // The finger that started this let go while the recorder was still coming
    // up. Send what there is, which is what releasing meant.
    if (_abandoned) {
      await _finishRecording(send: true);
      return;
    }
    // Nothing is holding a recording that had to stop and ask for permission —
    // the press ended when the dialog appeared. Leave it running with buttons.
    if (asked && !_handsFree && mounted) {
      setState(() => _handsFree = true);
    }
  }

  /// Ends the note, either sending it or throwing it away.
  ///
  /// Safe to call at any point, including when there is no recording — the press
  /// that ends one arrives through several different callbacks and more than one
  /// of them can fire for the same gesture.
  Future<void> _finishRecording({required bool send}) async {
    if (_starting && !_recording) {
      // Still coming up. [_startRecording] finishes the job once it has
      // something to finish.
      _abandoned = true;
      if (!send) unawaited(_discardRecording());
      return;
    }
    if (!_recording) return;

    _recordTimer?.cancel();
    _recordTimer = null;

    final held = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _recordingPath;
    }

    final file = File(path ?? _recordingPath ?? '');
    _recordingPath = null;
    _startedAt = null;

    if (mounted) {
      setState(() {
        _recording = false;
        _starting = false;
        _handsFree = false;
        _abandoned = false;
        _slid = 0;
        _recordedFor = Duration.zero;
      });
    }

    if (!send || path == null) {
      await _deleteQuietly(file);
      return;
    }

    // Too short to be a message — almost always a slipped finger on the button.
    if (held < _minimumRecording) {
      await _deleteQuietly(file);
      if (mounted) showToast('Hold the mic to record, or tap it to start.');
      return;
    }

    _emit(file.path, 'voice-note.m4a', 'audio/mp4');
  }

  /// Stops and drops whatever is being recorded, whatever state it is in.
  Future<void> _discardRecording() async {
    _startToken++;
    _recordTimer?.cancel();
    _recordTimer = null;
    _startedAt = null;

    try {
      await _recorder.cancel();
    } catch (_) {
      // Nothing was running, or the platform had already let go of it.
    }

    final path = _recordingPath;
    _recordingPath = null;
    if (path != null) await _deleteQuietly(File(path));

    if (!mounted) return;
    setState(() {
      _recording = false;
      _starting = false;
      _handsFree = false;
      _abandoned = false;
      _slid = 0;
      _recordedFor = Duration.zero;
    });
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (file.path.isNotEmpty && file.existsSync()) await file.delete();
    } catch (_) {
      // A temporary file the OS will clear out anyway.
    }
  }

  /// Tracks the finger while a held recording is running.
  void _onRecordingDrag(LongPressMoveUpdateDetails details) {
    if (!_recording && !_starting) return;
    if (_handsFree) return;

    final left = -details.offsetFromOrigin.dx;
    final up = -details.offsetFromOrigin.dy;

    if (left > _cancelDistance) {
      unawaited(_discardRecording());
      showToast('Voice note cancelled.');
      return;
    }
    // Slid up: the recording carries on without the finger, and the bar's
    // buttons take over.
    if (up > _lockDistance && left < 30) {
      setState(() {
        _handsFree = true;
        _slid = 0;
      });
      return;
    }

    final slid = left.clamp(0.0, _cancelDistance);
    if (slid != _slid) setState(() => _slid = slid);
  }

  static String _clock(Duration duration) =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!widget.enabled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Tokens.s4),
        color: scheme.surfaceContainerHigh,
        child: Row(
          children: [
            Icon(Icons.lock_rounded, size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                widget.lockedNote ?? 'You cannot post here.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final busy = _recording || _starting;
    final hasText = widget.controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!busy)
            IconButton(
              onPressed: _openAttachmentMenu,
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Attach',
            ),
          Expanded(
            child: busy
                ? _RecordingBar(
                    elapsed: _recordedFor,
                    slid: _slid,
                    cancelDistance: _cancelDistance,
                    handsFree: _handsFree,
                    starting: _starting,
                    clock: _clock,
                    onCancel: () => unawaited(_discardRecording()),
                  )
                : TextField(
                    controller: widget.controller,
                    onChanged: (value) {
                      widget.onChanged(value);
                      // Swaps the trailing button between mic and send.
                      setState(() {});
                    },
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Message…',
                      isDense: true,
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Tokens.rLg),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: Tokens.s2),
          if ((hasText || widget.sending) && !busy)
            IconButton.filled(
              onPressed: widget.sending ? null : widget.onSend,
              icon: widget.sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              tooltip: 'Send',
            )
          else
            // Hold to record and release to send, or tap to record hands-free.
            // Sliding left cancels; sliding up keeps it running without the
            // finger.
            //
            // Keyed, and never replaced while a recording is running: this is
            // the widget that owns the press. Swapping the whole composer out
            // for a recording bar — which is what used to happen — took the
            // gesture recogniser out of the tree with it, so the release that
            // was meant to send the note was delivered to nothing and the bar
            // sat there until the conversation was closed.
            GestureDetector(
              key: const ValueKey('mic'),
              onTap: () => busy
                  ? unawaited(_finishRecording(send: true))
                  : unawaited(_startRecording(handsFree: true)),
              onLongPressStart: (_) => unawaited(
                _startRecording(handsFree: false),
              ),
              onLongPressMoveUpdate: _onRecordingDrag,
              onLongPressEnd: (_) {
                if (_handsFree) return;
                unawaited(_finishRecording(send: true));
              },
              onLongPressCancel: () {
                // Fires both when a press is too short to be a long press — in
                // which case nothing has started and this does nothing — and
                // when the gesture is taken away mid-recording.
                if (_handsFree) return;
                unawaited(_finishRecording(send: true));
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: busy ? scheme.error : scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  busy
                      ? (_handsFree ? Icons.send_rounded : Icons.mic_rounded)
                      : Icons.mic_rounded,
                  size: 20,
                  color: busy ? scheme.onError : scheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What sits where the text field was while a note is being recorded.
///
/// It always carries a way out — the bin on the left ends the recording whatever
/// state the gesture is in, so a note can never strand the composer.
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.elapsed,
    required this.slid,
    required this.cancelDistance,
    required this.handsFree,
    required this.starting,
    required this.clock,
    required this.onCancel,
  });

  final Duration elapsed;

  /// How far the held finger has slid towards cancelling, in pixels.
  final double slid;
  final double cancelDistance;

  /// True once nothing is waiting on a finger.
  final bool handsFree;

  /// True while the microphone is still being opened.
  final bool starting;

  final String Function(Duration) clock;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = cancelDistance == 0 ? 0.0 : slid / cancelDistance;

    return Container(
      height: 46,
      padding: const EdgeInsets.only(left: 4, right: Tokens.s3),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(Tokens.rLg),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onCancel,
            icon: Icon(Icons.delete_outline_rounded,
                size: 19, color: scheme.error),
            tooltip: 'Cancel recording',
            visualDensity: VisualDensity.compact,
          ),
          _PulsingDot(color: scheme.error),
          const SizedBox(width: 7),
          Text(
            clock(elapsed),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: scheme.onErrorContainer,
            ),
          ),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Opacity(
              // Fades as the finger slides, so the hint gives way to the act.
              opacity: (1 - progress).clamp(0.35, 1.0),
              child: Text(
                starting
                    ? 'Starting…'
                    : handsFree
                        ? 'Tap send when you are done'
                        : slid > 8
                            ? 'Release to cancel'
                            : '← slide to cancel · ↑ slide to keep recording',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: slid > 8 ? FontWeight.w800 : FontWeight.w400,
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The blinking record light.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.25).animate(_controller),
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      );
}
