import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/live_repository.dart';
import '../../domain/models/live_session.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/in_app_browser.dart';
import 'live_engine.dart';

/// The live class room.
///
/// Port of the student half of `LivestreamPage`: the tutor's video on stage, the
/// class chat, raised hands, polls and the pinned message. Everything but the
/// video comes from the same `liveSessions/{id}` document the website writes, so a
/// student on a phone and one in a browser are in the same room.
class LivestreamScreen extends StatelessWidget {
  const LivestreamScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (context) => LiveEngine(live: context.read<LiveRepository>()),
        child: _LivestreamView(sessionId: sessionId),
      );
}

class _LivestreamView extends StatefulWidget {
  const _LivestreamView({required this.sessionId});

  final String sessionId;

  @override
  State<_LivestreamView> createState() => _LivestreamViewState();
}

class _LivestreamViewState extends State<_LivestreamView> {
  StreamSubscription<LiveSession?>? _sessionSub;
  StreamSubscription<List<LiveMessage>>? _messagesSub;
  LiveSession? _session;

  /// True once the door has been opened — so a session document arriving twice
  /// doesn't try to join twice.
  bool _joinRequested = false;

  bool _chatOpen = false;

  /// Held here rather than in the chat panel so the class chat keeps arriving
  /// while the panel is closed. Without it there is nothing to count, and the
  /// dot on the chat button can only ever guess.
  List<LiveMessage> _messages = const [];
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _sessionSub = context
        .read<LiveRepository>()
        .watchSession(widget.sessionId)
        .listen(_onSession);
    _messagesSub = context
        .read<LiveRepository>()
        .watchMessages(widget.sessionId)
        .listen(_onMessages);
  }

  void _onMessages(List<LiveMessage> messages) {
    if (!mounted) return;
    final myUid = context.read<SessionController>().account?.uid;
    final arrived = messages.length - _messages.length;

    setState(() {
      // Only what someone else said, and only while they weren't looking.
      if (!_chatOpen && arrived > 0) {
        _unread += messages
            .skip(messages.length - arrived)
            .where((m) => m.uid != myUid && !m.system)
            .length;
      }
      _messages = messages;
    });
  }

  void _toggleChat() => setState(() {
        _chatOpen = !_chatOpen;
        if (_chatOpen) _unread = 0;
      });

  void _onSession(LiveSession? session) {
    if (!mounted) return;
    setState(() => _session = session);
    if (session == null) return;

    final engine = context.read<LiveEngine>();
    engine.hostAgoraUid = session.hostAgoraUid;
    // The tutor pins by Firebase uid; the channel only knows Agora uids. The
    // viewer map is the bridge, exactly as it is on the website.
    engine.pinnedAgoraUid = session.featuredUid == null
        ? null
        : session.viewers
            .where((v) => v.uid == session.featuredUid)
            .map((v) => v.agoraUid)
            .firstOrNull;

    final uid = context.read<SessionController>().account?.uid;

    // Removed mid-class: leave the channel rather than sitting in a room the
    // tutor has put you out of.
    if (session.wasRemoved(uid)) {
      if (engine.isJoined) unawaited(_leave(silent: true));
      return;
    }

    // The tutor muted this student: drop their microphone to match. The room's
    // decision wins over the student's own toggle, and the headcount is told so
    // the tutor's gallery stops showing a live mic against a silenced student.
    if (session.isMuted(uid) && engine.microphoneOn) {
      unawaited(
        engine.setMicrophone(false).then((_) {
          if (mounted) unawaited(_syncPresence());
        }),
      );
    }

    if (!_joinRequested &&
        session.isLive &&
        session.channel.isNotEmpty &&
        !session.isWaiting(uid)) {
      _joinRequested = true;
      unawaited(_join(session));
    } else if (!_joinRequested) {
      // The three ways a room can sit on "Getting the class ready…" for ever.
      // Silent until now, and indistinguishable on screen from a join that is
      // simply taking its time.
      debugPrint('[live] not joining "${widget.sessionId}" — '
          'status ${session.status.name}, '
          'channel "${session.channel}", '
          'waiting ${session.isWaiting(uid)}');
    }
  }

  Future<void> _join(LiveSession session) async {
    final engine = context.read<LiveEngine>();
    await engine.join(session.channel);
    if (!mounted || !engine.isJoined) return;

    final controller = context.read<SessionController>();
    final uid = controller.account?.uid;
    if (uid == null) return;

    // Write into the headcount only after the channel is actually joined, so the
    // gallery never shows someone who isn't there. A rejected write is not worth
    // interrupting the class for — the student is in the room either way, they
    // just won't be counted in it.
    try {
      await context.read<LiveRepository>().enter(
            widget.sessionId,
            uid: uid,
            name: controller.profile?.displayName ?? 'Student',
            agoraUid: engine.myAgoraUid ?? 0,
          );
    } catch (_) {/* the tutor's headcount is off by one */}
  }

  /// Tears the connection down and joins again, for the Retry button.
  Future<void> _retry() async {
    final session = _session;
    final engine = context.read<LiveEngine>();
    if (session == null) return;

    if (engine.channel != null) {
      await engine.retry();
    } else {
      _joinRequested = false;
      _onSession(session);
      return;
    }

    if (!mounted || !engine.isJoined) return;
    final controller = context.read<SessionController>();
    final uid = controller.account?.uid;
    if (uid == null) return;
    try {
      await context.read<LiveRepository>().enter(
            widget.sessionId,
            uid: uid,
            name: controller.profile?.displayName ?? 'Student',
            agoraUid: engine.myAgoraUid ?? 0,
          );
    } catch (_) {/* as above */}
  }

  Future<void> _leave({bool silent = false}) async {
    // Everything the tear-down needs is read before the first await: the screen
    // is on its way out, and reaching back into the tree afterwards is exactly
    // what `use_build_context_synchronously` is warning about.
    final engine = context.read<LiveEngine>();
    final live = context.read<LiveRepository>();
    final uid = context.read<SessionController>().account?.uid;
    final navigator = Navigator.of(context);

    await engine.leave();
    if (uid != null) await live.leave(widget.sessionId, uid);
    if (!mounted || silent) return;
    navigator.pop();
  }

  Future<void> _toggleHand() async {
    final controller = context.read<SessionController>();
    final uid = controller.account?.uid;
    if (uid == null) return;

    final raised = _session?.handRaisedBy(uid) ?? false;
    try {
      await context.read<LiveRepository>().setHandRaised(
            widget.sessionId,
            uid: uid,
            name: controller.profile?.displayName ?? 'Student',
            raised: !raised,
          );
      if (mounted && !raised) {
        showToast('Hand raised — your tutor can see it.');
      }
    } catch (_) {
      if (mounted) {
        showToast('Could not raise your hand.', variant: ToastVariant.error);
      }
    }
  }

  Future<void> _toggleMicrophone() async {
    final engine = context.read<LiveEngine>();
    final uid = context.read<SessionController>().account?.uid;

    // A student the tutor has muted cannot unmute themselves — that is the whole
    // point of the tutor's control.
    if (!engine.microphoneOn && (_session?.isMuted(uid) ?? false)) {
      showToast('Your tutor has muted you.');
      return;
    }

    final wantOn = !engine.microphoneOn;
    final ok = await engine.setMicrophone(wantOn);
    if (!mounted) return;
    if (!ok) {
      showToast(
        'NLTC needs microphone access to let you speak.',
        variant: ToastVariant.error,
      );
      return;
    }
    if (wantOn) showToast('You are live — the class can hear you.');
    await _syncPresence();
  }

  /// The student's own camera, into the class.
  ///
  /// Same promotion the microphone does: turning it on makes them a broadcaster
  /// in the channel, so their tile appears in the tutor's gallery and on every
  /// other phone in the room, exactly as it does from the website.
  Future<void> _toggleCamera() async {
    final engine = context.read<LiveEngine>();
    final wantOn = !engine.cameraOn;

    final ok = await engine.setCamera(wantOn);
    if (!mounted) return;
    if (!ok) {
      showToast(
        'NLTC needs camera access to show you to the class.',
        variant: ToastVariant.error,
      );
      return;
    }
    if (wantOn) showToast('Your camera is on — the class can see you.');
    await _syncPresence();
  }

  /// Writes what this student is publishing back into the session document.
  ///
  /// The website's gallery draws its tiles from `viewers`, not from the channel,
  /// so without this a student broadcasting from the app would be heard and seen
  /// but still listed as sitting quietly with everything off.
  Future<void> _syncPresence() async {
    final engine = context.read<LiveEngine>();
    final controller = context.read<SessionController>();
    final uid = controller.account?.uid;
    if (uid == null) return;
    try {
      await context.read<LiveRepository>().updatePresence(
            widget.sessionId,
            uid: uid,
            name: controller.profile?.displayName ?? 'Student',
            agoraUid: engine.myAgoraUid ?? 0,
            camera: engine.cameraOn,
            microphone: engine.microphoneOn,
          );
    } catch (_) {/* the tutor's gallery is a beat behind; the stream is not */}
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _messagesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final engine = context.watch<LiveEngine>();
    final uid = context.read<SessionController>().account?.uid;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: BlueprintPalette.ink,
        body: SafeArea(
          child: session == null
              ? const Center(child: CircularProgressIndicator())
              : session.wasRemoved(uid)
                  ? _RoomNotice(
                      icon: Icons.person_off_rounded,
                      title: 'You were removed from this class',
                      message: 'Your tutor removed you from the room. Speak to '
                          'them if you think this is a mistake.',
                      onExit: () => Navigator.of(context).pop(),
                    )
                  : session.isWaiting(uid)
                      ? _RoomNotice(
                          icon: Icons.hourglass_top_rounded,
                          title: 'Waiting room',
                          message: 'Your tutor will let you in shortly — hold on.',
                          onExit: () => Navigator.of(context).pop(),
                        )
                      : session.hasEnded
                          ? _RoomNotice(
                              icon: Icons.waving_hand_rounded,
                              title: 'This class has ended',
                              message: 'Thanks for joining. Check Live Classes '
                                  'for the next session.',
                              onExit: () => Navigator.of(context).pop(),
                            )
                          : _Room(
                              session: session,
                              engine: engine,
                              uid: uid,
                              chatOpen: _chatOpen,
                              messages: _messages,
                              unread: _unread,
                              onToggleChat: _toggleChat,
                              onToggleHand: _toggleHand,
                              onToggleMicrophone: _toggleMicrophone,
                              onToggleCamera: _toggleCamera,
                              onLeave: _leave,
                              onRetry: _retry,
                              sessionId: widget.sessionId,
                            ),
        ),
      ),
    );
  }
}

/// The room, once the student is actually in it.
class _Room extends StatelessWidget {
  const _Room({
    required this.session,
    required this.engine,
    required this.uid,
    required this.chatOpen,
    required this.messages,
    required this.unread,
    required this.onToggleChat,
    required this.onToggleHand,
    required this.onToggleMicrophone,
    required this.onToggleCamera,
    required this.onLeave,
    required this.onRetry,
    required this.sessionId,
  });

  final LiveSession session;
  final LiveEngine engine;
  final String? uid;
  final bool chatOpen;
  final List<LiveMessage> messages;
  final int unread;
  final VoidCallback onToggleChat;
  final VoidCallback onToggleHand;
  final VoidCallback onToggleMicrophone;
  final VoidCallback onToggleCamera;
  final Future<void> Function({bool silent}) onLeave;
  final Future<void> Function() onRetry;
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final handRaised = session.handRaisedBy(uid);

    return Column(
      children: [
        _RoomHeader(session: session, onLeave: () => onLeave()),
        Expanded(
          // Stacked rather than swapped. Replacing the stage with the chat tore
          // down the platform view the video renders into, and standing a new one
          // up on the way back is what made the stream come back black — the
          // class kept playing, the student just stopped seeing it.
          child: Stack(
            children: [
              Positioned.fill(
                child: _Stage(
                  session: session,
                  engine: engine,
                  uid: uid,
                  onRetry: onRetry,
                ),
              ),
              if (chatOpen)
                Positioned.fill(
                  child: ColoredBox(
                    color: BlueprintPalette.ink.withValues(alpha: 0.94),
                    child: _ChatPanel(
                      sessionId: sessionId,
                      session: session,
                      messages: messages,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (session.pinnedMessage != null && !chatOpen)
          _PinnedMessage(message: session.pinnedMessage!),
        if (session.poll != null && !chatOpen)
          _PollCard(sessionId: sessionId, poll: session.poll!, uid: uid),
        _RoomDock(
          engine: engine,
          handRaised: handRaised,
          chatOpen: chatOpen,
          // What was actually said while they weren't looking. This used to read
          // `session.typing.isNotEmpty`, which lit the dot up from the student's
          // own keystrokes and said nothing at all about missed messages.
          unread: unread,
          someoneTyping:
              session.typing.keys.any((typist) => typist != uid),
          mutedByTutor: session.isMuted(uid),
          onToggleChat: onToggleChat,
          onToggleHand: onToggleHand,
          onToggleMicrophone: onToggleMicrophone,
          onToggleCamera: onToggleCamera,
          onLeave: () => onLeave(),
        ),
      ],
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.session, required this.onLeave});

  final LiveSession session;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.s3, Tokens.s2, Tokens.s3, 0),
        child: Row(
          children: [
            IconButton(
              onPressed: onLeave,
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              tooltip: 'Leave class',
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: GoogleFonts.fraunces(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      if (session.hostName != null) session.hostName!,
                      '${session.watching} in the room',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: BlueprintPalette.error,
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
}

/// The video stage.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.session,
    required this.engine,
    required this.uid,
    required this.onRetry,
  });

  final LiveSession session;
  final LiveEngine engine;
  final String? uid;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final stage = engine.stage;
    final rtcEngine = engine.engine;
    final connection = engine.rtcConnection;
    final canRender = stage != null &&
        stage.hasVideo &&
        rtcEngine != null &&
        connection != null;

    // Everyone else with a camera on, plus this student's own preview. The
    // website drops them all into a filmstrip beside the stage; on a phone it
    // goes underneath, which is the only place a 16:9 stage leaves for it.
    final strip = engine.others;
    final showStrip =
        rtcEngine != null && (strip.isNotEmpty || engine.cameraOn);

    return Padding(
      padding: const EdgeInsets.all(Tokens.s3),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.rMd),
              child: ColoredBox(
                color: BlueprintPalette.darkSurface,
                child: switch (engine.connection) {
                  LiveConnection.idle => const _StageMessage(
                      icon: Icons.cast_connected_rounded,
                      message: 'Getting the class ready…',
                      busy: true,
                    ),
                  LiveConnection.joining => const _StageMessage(
                      icon: Icons.cast_connected_rounded,
                      message: 'Joining the class…',
                      busy: true,
                    ),
                  LiveConnection.failed => _StageMessage(
                      icon: Icons.wifi_off_rounded,
                      message: engine.error ??
                          'Could not join. Check your connection.',
                      // The technical cause, small and underneath. A student who
                      // screenshots this gives their tutor something to act on;
                      // without it every failure looked like bad Wi-Fi.
                      detail: engine.errorDetail,
                      onRetry: onRetry,
                    ),
                  // Reconnecting keeps whatever was last on screen, with a
                  // banner over it — see below. Pulling the tutor off the stage
                  // for a two-second blip is worse than a frozen frame.
                  _ when !canRender => _StageMessage(
                      icon: Icons.videocam_off_rounded,
                      message: "Your tutor's camera is off — you can still hear "
                          'them.',
                      overlay: engine.connection == LiveConnection.reconnecting
                          ? 'Reconnecting…'
                          : null,
                    ),
                  _ => Stack(
                      children: [
                        Positioned.fill(
                          child: RemoteVideo(
                            rtcEngine: rtcEngine,
                            connection: connection,
                            remoteUid: stage.agoraUid,
                          ),
                        ),
                        if (engine.connection == LiveConnection.reconnecting)
                          const Positioned(
                            top: Tokens.s2,
                            left: 0,
                            right: 0,
                            child: Center(child: _ReconnectingChip()),
                          ),
                      ],
                    ),
                },
              ),
            ),
          ),
          if (session.raisedHands.isNotEmpty) ...[
            const SizedBox(height: Tokens.s2),
            _HandsStrip(hands: session.raisedHands, myUid: uid),
          ],
          if (showStrip) ...[
            const SizedBox(height: Tokens.s2),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // The student's own camera leads the strip — the first thing
                  // you check after turning it on is whether you are in frame.
                  if (engine.cameraOn)
                    _StripTile(
                      label: 'You',
                      speaking: engine.selfSpeaking,
                      isSelf: true,
                      onFlip: engine.switchCamera,
                      child: LocalVideo(rtcEngine: rtcEngine),
                    ),
                  for (final feed in strip)
                    if (connection != null)
                      _StripTile(
                        label: feed.agoraUid == engine.hostAgoraUid
                            ? (session.hostName ?? 'Tutor')
                            : session.viewers
                                    .where((v) => v.agoraUid == feed.agoraUid)
                                    .map((v) => v.name)
                                    .firstOrNull ??
                                'Student',
                        speaking: feed.speaking,
                        isSelf: false,
                        child: RemoteVideo(
                          rtcEngine: rtcEngine,
                          connection: connection,
                          remoteUid: feed.agoraUid,
                        ),
                      ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One tile in the strip under the stage.
class _StripTile extends StatelessWidget {
  const _StripTile({
    required this.label,
    required this.speaking,
    required this.isSelf,
    required this.child,
    this.onFlip,
  });

  final String label;
  final bool speaking;
  final bool isSelf;
  final Widget child;

  /// Front camera ↔ back. Only the student's own tile has one — it lives here
  /// rather than in the dock because it is meaningless until you can see what it
  /// is about to change, and the dock has no room left.
  final VoidCallback? onFlip;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: Tokens.s2),
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.rSm),
              border: Border.all(
                color: speaking
                    ? BlueprintPalette.success
                    : Colors.white.withValues(alpha: 0.14),
                width: speaking ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.rSm - 1),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: BlueprintPalette.darkSurfaceHigh,
                    child: child,
                  ),
                  if (onFlip != null)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onFlip,
                          child: const Padding(
                            padding: EdgeInsets.all(5),
                            child: Icon(
                              Icons.flip_camera_ios_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: isSelf
                              ? BlueprintPalette.b200
                              : Colors.white.withValues(alpha: 0.9),
                        ),
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

/// A remote participant's video.
///
/// The controller is built once and kept for as long as the same person is on
/// screen. That is the whole point of this widget: the engine notifies its
/// listeners several times a second (the speaking indicator alone fires every
/// 400ms), and building a fresh `VideoViewController` on each of those rebuilds
/// tears the platform view down and stands a new one up before it has drawn a
/// frame — which shows as a class you can hear but not see.
class RemoteVideo extends StatefulWidget {
  const RemoteVideo({
    super.key,
    required this.rtcEngine,
    required this.connection,
    required this.remoteUid,
  });

  final RtcEngine rtcEngine;

  /// Both halves of it matter. A remote canvas is bound through
  /// `setupRemoteVideoEx`, which finds the channel by channel id **and** local
  /// uid; a connection missing the uid matches only a channel joined as uid 0,
  /// and this app joins as the uid the backend derives from the account. That
  /// mismatch bound every tile to nothing — the class arrived, decoded, and was
  /// drawn onto a canvas the SDK had never attached.
  final RtcConnection connection;

  final int remoteUid;

  @override
  State<RemoteVideo> createState() => _RemoteVideoState();
}

class _RemoteVideoState extends State<RemoteVideo> {
  late VideoViewController _controller = _build();

  VideoViewController _build() => VideoViewController.remote(
        rtcEngine: widget.rtcEngine,
        canvas: VideoCanvas(uid: widget.remoteUid),
        connection: widget.connection,
      );

  @override
  void didUpdateWidget(RemoteVideo old) {
    super.didUpdateWidget(old);
    // Only when it is genuinely a different feed — the tutor pinning someone
    // else, or a reconnect onto a new channel.
    if (old.remoteUid != widget.remoteUid ||
        old.connection.channelId != widget.connection.channelId ||
        old.connection.localUid != widget.connection.localUid ||
        !identical(old.rtcEngine, widget.rtcEngine)) {
      _controller = _build();
    }
  }

  @override
  Widget build(BuildContext context) => AgoraVideoView(
        // Keyed on the feed as well, so Flutter replaces the platform view
        // rather than trying to rebind a live one to a different uid.
        key: ValueKey(
          '${widget.connection.channelId}:'
          '${widget.connection.localUid}:${widget.remoteUid}',
        ),
        controller: _controller,
      );
}

/// The student's own camera preview, with the same stable-controller rule.
class LocalVideo extends StatefulWidget {
  const LocalVideo({super.key, required this.rtcEngine});

  final RtcEngine rtcEngine;

  @override
  State<LocalVideo> createState() => _LocalVideoState();
}

class _LocalVideoState extends State<LocalVideo> {
  late VideoViewController _controller = _build();

  VideoViewController _build() => VideoViewController(
        rtcEngine: widget.rtcEngine,
        canvas: const VideoCanvas(uid: 0),
      );

  @override
  void didUpdateWidget(LocalVideo old) {
    super.didUpdateWidget(old);
    if (!identical(old.rtcEngine, widget.rtcEngine)) _controller = _build();
  }

  @override
  Widget build(BuildContext context) =>
      AgoraVideoView(controller: _controller);
}

class _StageMessage extends StatelessWidget {
  const _StageMessage({
    required this.icon,
    required this.message,
    this.busy = false,
    this.onRetry,
    this.overlay,
    this.detail,
  });

  final IconData icon;
  final String message;
  final bool busy;

  /// The technical cause, in small print under the message — `api 403`,
  /// `agora -17`. Present only when something failed.
  final String? detail;

  /// Offered whenever the room is recoverable. A student who cannot get in and
  /// has no button to press leaves the class and does not come back.
  final Future<void> Function()? onRetry;

  /// A short note above the message — "Reconnecting…" — for when something is
  /// happening that the message itself does not cover.
  final String? overlay;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (overlay != null) ...[
                const _ReconnectingChip(),
                const SizedBox(height: Tokens.s4),
              ],
              if (busy)
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                Icon(icon, size: 34, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(height: Tokens.s4),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: Tokens.s2),
                SelectableText(
                  detail!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: Tokens.s5),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      );
}

/// The badge shown while the SDK is getting back into the channel.
class _ReconnectingChip extends StatelessWidget {
  const _ReconnectingChip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: BlueprintPalette.warning,
          borderRadius: BorderRadius.circular(100),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 7),
            Text(
              'Reconnecting…',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
}

/// Who has a hand up.
class _HandsStrip extends StatelessWidget {
  const _HandsStrip({required this.hands, required this.myUid});

  final Map<String, String> hands;
  final String? myUid;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s3,
          vertical: Tokens.s2,
        ),
        decoration: BoxDecoration(
          color: BlueprintPalette.warning.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(Tokens.rSm),
        ),
        child: Row(
          children: [
            const Text('✋', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                hands.entries
                    .map((e) => e.key == myUid ? 'You' : e.value)
                    .join(', '),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: BlueprintPalette.warning,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

class _PinnedMessage extends StatelessWidget {
  const _PinnedMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s2),
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s3,
          vertical: Tokens.s2,
        ),
        decoration: BoxDecoration(
          color: BlueprintPalette.b800,
          borderRadius: BorderRadius.circular(Tokens.rSm),
        ),
        child: Row(
          children: [
            const Icon(Icons.push_pin_rounded, size: 13, color: Colors.white),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
}

/// The tutor's poll, and this student's vote in it.
class _PollCard extends StatelessWidget {
  const _PollCard({
    required this.sessionId,
    required this.poll,
    required this.uid,
  });

  final String sessionId;
  final LivePoll poll;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    final myVote = poll.voteOf(uid);

    return Container(
      margin: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s2),
      padding: const EdgeInsets.all(Tokens.s3),
      decoration: BoxDecoration(
        color: BlueprintPalette.darkSurfaceHigh,
        borderRadius: BorderRadius.circular(Tokens.rSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  poll.question,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              if (!poll.open)
                Text(
                  'CLOSED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Tokens.s2),
          for (var i = 0; i < poll.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _PollOption(
                label: poll.options[i],
                votes: poll.countFor(i),
                total: poll.totalVotes,
                chosen: myVote == i,
                // Results are only revealed once this student has voted, so an
                // early answer doesn't sway the rest of the class.
                showResults: myVote != null || !poll.open,
                onTap: poll.open && uid != null
                    ? () => context.read<LiveRepository>().votePoll(
                          sessionId,
                          uid: uid!,
                          optionIndex: i,
                        )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.label,
    required this.votes,
    required this.total,
    required this.chosen,
    required this.showResults,
    required this.onTap,
  });

  final String label;
  final int votes;
  final int total;
  final bool chosen;
  final bool showResults;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0.0 : votes / total;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.rXs),
      child: Stack(
        children: [
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(Tokens.rXs),
              border: chosen
                  ? Border.all(color: BlueprintPalette.b300, width: 1.5)
                  : null,
            ),
          ),
          if (showResults)
            FractionallySizedBox(
              widthFactor: share,
              child: Container(
                height: 32,
                decoration: BoxDecoration(
                  color: BlueprintPalette.b500.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(Tokens.rXs),
                ),
              ),
            ),
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                if (chosen) ...[
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showResults)
                  Text(
                    '${(share * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
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

/// The class chat.
class _ChatPanel extends StatefulWidget {
  const _ChatPanel({
    required this.sessionId,
    required this.session,
    required this.messages,
  });

  final String sessionId;
  final LiveSession session;

  /// Owned by the room, so the class chat keeps arriving with the panel closed.
  final List<LiveMessage> messages;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Timer? _typingTimer;
  DateTime? _typingSince;
  bool _sending = false;

  /// Matches the conversation screen: often enough that the room never sees the
  /// indicator flicker, rarely enough that it is not a write per keystroke on a
  /// document the whole class is subscribed to.
  static const _typingRefresh = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _scrollToEnd();
  }

  @override
  void didUpdateWidget(_ChatPanel old) {
    super.didUpdateWidget(old);
    // Newest at the bottom, so a new message should bring itself into view.
    if (old.messages.length != widget.messages.length) _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _stopTyping();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Tells the room this student is writing.
  ///
  /// The room already draws everyone else's marker from `session.typing`, but
  /// nothing ever wrote this student's — so the indicator worked in one direction
  /// only, and a student on a phone appeared to type nothing at all.
  void _onTyping(String value) {
    final uid = context.read<SessionController>().account?.uid;
    final controller = context.read<SessionController>();
    if (uid == null) return;

    if (value.trim().isEmpty) {
      _stopTyping();
      return;
    }

    final since = _typingSince;
    if (since == null || DateTime.now().difference(since) >= _typingRefresh) {
      _typingSince = DateTime.now();
      unawaited(
        context.read<LiveRepository>().setTyping(
              widget.sessionId,
              uid: uid,
              name: controller.profile?.displayName ?? 'Student',
              typing: true,
            ),
      );
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    _typingTimer = null;
    if (_typingSince == null) return;
    _typingSince = null;

    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return;
    unawaited(
      context.read<LiveRepository>().setTyping(
            widget.sessionId,
            uid: uid,
            name: '',
            typing: false,
          ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final controller = context.read<SessionController>();
    final uid = controller.account?.uid;
    if (uid == null) return;

    setState(() => _sending = true);
    _controller.clear();
    _stopTyping();
    try {
      await context.read<LiveRepository>().sendMessage(
            widget.sessionId,
            uid: uid,
            name: controller.profile?.displayName ?? 'Student',
            text: text,
          );
    } catch (_) {
      if (mounted) {
        _controller.text = text;
        showToast('Message not sent. Try again.', variant: ToastVariant.error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = context.read<SessionController>().account?.uid;
    final typists = widget.session.typing.entries
        .where((e) => e.key != myUid)
        .map((e) => e.value)
        .toList();

    final messages = widget.messages;

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    'No messages yet — say hello.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s3,
                    vertical: Tokens.s2,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _ChatLine(
                    message: messages[i],
                    isMine: messages[i].uid == myUid,
                  ),
                ),
        ),
        if (typists.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: Tokens.s4, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                typists.length == 1
                    ? '${typists.first} is typing…'
                    : '${typists.take(2).join(' & ')} are typing…',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  textInputAction: TextInputAction.send,
                  onChanged: _onTyping,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Message the class…',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Tokens.s2),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send_rounded, size: 18),
                tooltip: 'Send',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatLine extends StatelessWidget {
  const _ChatLine({required this.message, required this.isMine});

  final LiveMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Text(
            message.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isMine ? 'You' : message.name,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: message.isHost
                      ? BlueprintPalette.warning
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
              if (message.isHost) ...[
                const SizedBox(width: 4),
                const Text(
                  'TUTOR',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: BlueprintPalette.warning,
                  ),
                ),
              ],
              if (message.createdAt != null) ...[
                const SizedBox(width: 6),
                Text(
                  DateFormat('HH:mm').format(message.createdAt!),
                  style: TextStyle(
                    fontSize: 9.5,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: isMine
                  ? BlueprintPalette.b600
                  : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Tokens.rSm),
            ),
            // A tutor dropping a past-question link into the class chat is half
            // the reason this chat exists; it opens in the app so the student is
            // still in the class when they come back from it.
            child: LinkifiedText(
              text: message.text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The control dock along the bottom.
///
/// Microphone and camera first, the way the website's dock reads: they are the
/// two controls that decide whether a student is taking part or just watching.
class _RoomDock extends StatelessWidget {
  const _RoomDock({
    required this.engine,
    required this.handRaised,
    required this.chatOpen,
    required this.unread,
    required this.someoneTyping,
    required this.mutedByTutor,
    required this.onToggleChat,
    required this.onToggleHand,
    required this.onToggleMicrophone,
    required this.onToggleCamera,
    required this.onLeave,
  });

  final LiveEngine engine;
  final bool handRaised;
  final bool chatOpen;
  final int unread;
  final bool someoneTyping;

  /// The tutor has silenced this student. The button stays live — pressing it is
  /// how they find out why nothing happened — but it reads as blocked.
  final bool mutedByTutor;

  final VoidCallback onToggleChat;
  final VoidCallback onToggleHand;
  final VoidCallback onToggleMicrophone;
  final VoidCallback onToggleCamera;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    // Publishing needs to be actually in the channel; everything else works from
    // the moment the room is on screen.
    final live = engine.isInRoom;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        Tokens.s2,
        Tokens.s2,
        Tokens.s2,
        Tokens.s3,
      ),
      decoration: const BoxDecoration(color: BlueprintPalette.darkSurface),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _DockButton(
            icon: mutedByTutor
                ? Icons.mic_off_rounded
                : engine.microphoneOn
                    ? Icons.mic_rounded
                    : Icons.mic_off_rounded,
            label: mutedByTutor
                ? 'Muted'
                : engine.microphoneOn
                    ? 'Mute'
                    : 'Speak',
            active: engine.microphoneOn,
            onTap: live ? onToggleMicrophone : null,
          ),
          _DockButton(
            icon: engine.cameraOn
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            label: engine.cameraOn ? 'Hide' : 'Video',
            active: engine.cameraOn,
            onTap: live ? onToggleCamera : null,
          ),
          _DockButton(
            icon: Icons.back_hand_rounded,
            label: handRaised ? 'Lower' : 'Hand up',
            active: handRaised,
            onTap: onToggleHand,
          ),
          _DockButton(
            icon: Icons.chat_bubble_rounded,
            label: 'Chat',
            active: chatOpen,
            // A count when there is something to read, a plain dot when
            // someone is only part-way through saying it.
            badgeCount: chatOpen ? 0 : unread,
            badge: !chatOpen && unread == 0 && someoneTyping,
            onTap: onToggleChat,
          ),
          _DockButton(
            icon: engine.speakerOn
                ? Icons.volume_up_rounded
                : Icons.hearing_rounded,
            label: engine.speakerOn ? 'Speaker' : 'Earpiece',
            active: false,
            onTap: live ? () => engine.setSpeaker(!engine.speakerOn) : null,
          ),
          _DockButton(
            icon: Icons.call_end_rounded,
            label: 'Leave',
            active: false,
            danger: true,
            onTap: onLeave,
          ),
        ],
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.danger = false,
    this.badge = false,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final bool danger;

  /// A plain dot — something is happening, but there is nothing to count.
  final bool badge;

  /// How many unread, when that is knowable. Wins over [badge].
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? BlueprintPalette.error
        : active
            ? BlueprintPalette.b500
            : Colors.white.withValues(alpha: 0.12);
    final foreground =
        onTap == null ? Colors.white.withValues(alpha: 0.35) : Colors.white;

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rSm),
        // Six controls have to sit on one row of a 360dp phone, so the tile is
        // sized rather than left to its label — "Earpiece" is twice the width of
        // "Chat" and would otherwise push the row off the screen.
        child: SizedBox(
          width: 54,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: background,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, size: 20, color: foreground),
                    ),
                    if (badgeCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          constraints:
                              const BoxConstraints(minWidth: 17, minHeight: 17),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: BlueprintPalette.error,
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: BlueprintPalette.darkSurface,
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    else if (badge)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: BlueprintPalette.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.7),
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

/// The room saying why you can't be in it — removed, waiting, or the class is over.
class _RoomNotice extends StatelessWidget {
  const _RoomNotice({
    required this.icon,
    required this.title,
    required this.message,
    required this.onExit,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: Colors.white.withValues(alpha: 0.6)),
              const SizedBox(height: Tokens.s5),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.fraunces(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: Tokens.s3),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: Tokens.s6),
              FilledButton(
                onPressed: onExit,
                child: const Text('Back to Live Classes'),
              ),
            ],
          ),
        ),
      );
}
