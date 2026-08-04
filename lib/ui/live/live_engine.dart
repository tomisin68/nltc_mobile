import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/repositories/live_repository.dart';
import '../../data/services/api_client.dart';

/// Everything the join path says about itself, under one tag.
///
/// A failed join used to leave nothing behind but "could not join the class" on
/// a student's screen — no step, no code, no way to tell a refused token apart
/// from a dead network. Filtering `flutter logs` (or `adb logcat -s flutter`) on
/// `[live]` is now the whole story of an attempt. Never carries a token or an
/// id token: this prints in release builds too.
void _log(String message) => debugPrint('[live] $message');

/// A remote participant's published tracks, as Agora reports them.
@immutable
class RemoteFeed {
  const RemoteFeed({
    required this.agoraUid,
    this.hasVideo = false,
    this.hasAudio = false,
    this.speaking = false,
  });

  final int agoraUid;
  final bool hasVideo;
  final bool hasAudio;
  final bool speaking;

  RemoteFeed copyWith({bool? hasVideo, bool? hasAudio, bool? speaking}) =>
      RemoteFeed(
        agoraUid: agoraUid,
        hasVideo: hasVideo ?? this.hasVideo,
        hasAudio: hasAudio ?? this.hasAudio,
        speaking: speaking ?? this.speaking,
      );
}

/// Where a join attempt got to.
enum LiveConnection {
  idle,
  joining,
  joined,

  /// In the channel, but the network dropped and the SDK is getting back in.
  /// Distinct from [joining] because the room is still on screen and the student
  /// should be told to wait rather than shown a spinner over everything.
  reconnecting,

  failed,
}

/// Drives the Agora RTC engine for one class.
///
/// Wraps the plugin so the screen never touches it directly: the screen asks to
/// join, and reads [remotes] and [connection] to draw. Native RTC rather than a
/// WebView is deliberate — a WebView cannot hold a reliable audio session on
/// mid-range Android, which is most of the devices this app runs on.
///
/// A student joins as audience and is promoted to broadcaster the moment they
/// turn their own microphone or camera on, exactly as the website does it: the
/// audience token the backend issues carries no publishing restriction, and the
/// tutor's mute and removal controls are what actually govern who speaks.
class LiveEngine extends ChangeNotifier {
  LiveEngine({required LiveRepository live}) : _live = live;

  final LiveRepository _live;

  RtcEngine? _engine;

  /// Bounds the "Joining the class…" spinner.
  ///
  /// A join that neither succeeds nor errors is the worst of the three outcomes:
  /// with nothing to time it out, the student sat watching a spinner with no way
  /// to tell whether to wait or to leave and come back.
  Timer? _joinTimeout;

  static const _joinDeadline = Duration(seconds: 25);

  /// Whether the microphone was granted. Watching never needs it; speaking does,
  /// and knowing in advance is what lets the dock explain itself.
  bool _canPublish = false;

  LiveConnection _connection = LiveConnection.idle;
  String? _error;
  String? _errorDetail;

  final Map<int, RemoteFeed> _remotes = {};
  int? _myAgoraUid;
  String? _channel;

  bool _microphoneOn = false;
  bool _cameraOn = false;
  bool _speakerOn = true;
  bool _frontCamera = true;
  bool _selfSpeaking = false;
  bool _disposed = false;

  int? _hostAgoraUid;
  int? _pinnedAgoraUid;

  /// The tutor's numeric uid, once the session document names it. What tells the
  /// tutor's stream apart from a co-presenting student's.
  ///
  /// The document usually arrives after the channel is already joined, so
  /// setting this has to be able to move the stage — hence the notify.
  int? get hostAgoraUid => _hostAgoraUid;

  set hostAgoraUid(int? value) {
    if (_hostAgoraUid == value) return;
    _hostAgoraUid = value;
    notifyListeners();
  }

  /// Whoever the tutor has put on everyone's stage — a student answering a
  /// question, or the tutor's own screen share.
  ///
  /// The website resolves `featuredUid` to an Agora uid through the viewer map
  /// and pins that tile for the whole room; without this the phone quietly
  /// ignored the tutor and kept showing whoever it had picked itself.
  int? get pinnedAgoraUid => _pinnedAgoraUid;

  set pinnedAgoraUid(int? value) {
    if (_pinnedAgoraUid == value) return;
    _pinnedAgoraUid = value;
    notifyListeners();
  }

  LiveConnection get connection => _connection;
  String? get error => _error;

  /// The short technical cause under the friendly message — `api 403`,
  /// `agora -17`, `FirebaseAuthException`.
  ///
  /// Three unrelated failures all read "check your connection", and neither the
  /// student reporting it nor the tutor receiving the report could tell them
  /// apart. This is the line that makes a screenshot worth something.
  String? get errorDetail => _errorDetail;

  bool get isJoined => _connection == LiveConnection.joined;

  /// True while there is a room to draw, even if the network is misbehaving.
  bool get isInRoom =>
      _connection == LiveConnection.joined ||
      _connection == LiveConnection.reconnecting;

  /// Everyone publishing, most recently joined last.
  List<RemoteFeed> get remotes => _remotes.values.toList(growable: false);

  /// The feed to put on the main stage.
  ///
  /// Same order the website's `featured` uses: an explicit pin, then the tutor,
  /// then whoever is talking, then anyone at all with a camera on — falling back
  /// to the tutor's tile so a class with every camera off still names who is
  /// running it rather than going blank.
  RemoteFeed? get stage {
    final pinned = _pinnedAgoraUid == null ? null : _remotes[_pinnedAgoraUid];
    if (pinned != null && pinned.hasVideo) return pinned;

    final host = hostAgoraUid == null ? null : _remotes[hostAgoraUid];
    if (host != null && host.hasVideo) return host;

    final talking = _remotes.values
        .where((feed) => feed.hasVideo && feed.speaking)
        .firstOrNull;
    if (talking != null) return talking;

    return _remotes.values.where((feed) => feed.hasVideo).firstOrNull ?? host;
  }

  /// Everyone else with a camera on, for the strip under the stage.
  List<RemoteFeed> get others {
    final featured = stage?.agoraUid;
    return _remotes.values
        .where((feed) => feed.hasVideo && feed.agoraUid != featured)
        .toList(growable: false);
  }

  int? get myAgoraUid => _myAgoraUid;
  bool get microphoneOn => _microphoneOn;
  bool get cameraOn => _cameraOn;
  bool get speakerOn => _speakerOn;
  bool get frontCamera => _frontCamera;

  /// True while this student's own voice is carrying — the local half of the
  /// speaking ring the tutor's tile gets.
  bool get selfSpeaking => _selfSpeaking;

  /// True once this student is publishing anything at all.
  bool get isBroadcasting => _microphoneOn || _cameraOn;

  /// The engine, for the video views to render into. Null before joining.
  RtcEngine? get engine => _engine;

  /// The joined connection, as the SDK identifies it.
  ///
  /// Rendering a remote tile goes through `setupRemoteVideoEx`, which looks the
  /// channel up by **both** halves of this pair. Handing it a connection without
  /// the local uid matches only a channel joined with uid 0 — every other join
  /// silently bound the canvas to nothing, which is why the class could be heard
  /// but never seen.
  RtcConnection? get rtcConnection {
    final channel = _channel;
    final uid = _myAgoraUid;
    if (channel == null || uid == null) return null;
    return RtcConnection(channelId: channel, localUid: uid);
  }

  // ─── Joining ───────────────────────────────────────────────────────────────

  /// Joins [channel] as audience.
  ///
  /// Microphone permission is asked for up front even though a student joins
  /// muted: being invited to speak happens mid-class, where a permission dialog
  /// means missing the question you were asked. A refusal is not fatal — watching
  /// is still watching — so the result is only remembered, not acted on.
  Future<void> join(String channel) async {
    if (_connection == LiveConnection.joining || isInRoom) {
      _log('join("$channel") ignored — already ${_connection.name}');
      return;
    }

    _log('join("$channel") starting');
    _connection = LiveConnection.joining;
    _error = null;
    _errorDetail = null;
    _channel = channel;
    _remotes.clear();
    notifyListeners();

    _canPublish = await _requestMicrophonePermission();
    _log('microphone permission granted: $_canPublish');

    try {
      // Serialised, and with one full teardown-and-retry inside: see
      // [_serialized] and [_openChannel] for what the native singleton does to
      // anything less careful.
      await _serialized(() => _openChannel(channel));
      _log('joinChannel handed off — waiting for the server');
    } catch (e, stack) {
      _joinTimeout?.cancel();
      _joinTimeout = null;
      _log('join failed at $_step: ${e.runtimeType}: $e');
      // An ApiException already says what the server answered; anything else is
      // a surprise, and the frame it came from is the only way to place it.
      if (e is! ApiException) _log('$stack');
      _error = switch (e) {
        ApiException() => e.message,
        // The SDK's own code is the one thing that makes a report from a student
        // actionable, so it survives into the message.
        AgoraRtcException() => 'Could not join the class (${e.code}).',
        Exception() =>
          'Could not join the class. Check your connection and try again.',
        _ => '$e',
      };
      _errorDetail = '${_detail(e)} at $_step';
      _connection = LiveConnection.failed;
      notifyListeners();
    }
  }

  /// Which SDK call is in flight, for the error line.
  ///
  /// Every step of a join throws the same `AgoraRtcException`, so a bare code
  /// said nothing about where it came from — `-3` from `initialize` is a broken
  /// engine, `-3` from `joinChannel` is a stale one, and they need opposite
  /// fixes. This is what tells them apart from a student's screenshot.
  String _step = 'idle';

  /// Everything that touches the process-wide native engine, one at a time.
  ///
  /// `createAgoraRtcEngine()` hands out a single shared instance for the whole
  /// app, and the plugin's own `initialize` returns early — "if previous
  /// initialization still in progress, skip it" — leaving the caller to go on
  /// and use an engine that is not ready. That is precisely ERR_NOT_READY (-3),
  /// and two `LiveEngine`s overlapping by a single frame is enough to cause it:
  /// a screen rebuilt, or a retry racing the `dispose` of the room it replaced,
  /// because `dispose` cannot await the teardown it starts. This queue is what
  /// makes the overlap impossible rather than unlikely.
  static Future<void> _engineWork = Future<void>.value();

  static Future<T> _serialized<T>(Future<T> Function() work) {
    final result = _engineWork.then((_) => work());
    // The queue must survive a failed attempt, or one bad join would wedge every
    // later one behind an error that has already been handled.
    _engineWork = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Stands the engine up and asks for the channel, once more from scratch if
  /// the SDK refuses the first attempt.
  ///
  /// Both things a retry has to undo are native and shared: a half-initialised
  /// engine, and the ghost of this account's previous connection — the Agora uid
  /// is derived from the account, so every attempt collides with the last one
  /// until the server lets it go. A full teardown plus a fresh token clears
  /// both, which is what the website has always done here and the phone did not.
  Future<void> _openChannel(String channel) async {
    for (var attempt = 1;; attempt++) {
      try {
        await _attemptChannel(channel);
        return;
      } on AgoraRtcException catch (e) {
        if (attempt >= 2) rethrow;
        _log('attempt $attempt refused at $_step (${e.code}: ${e.message}) — '
            'tearing down and trying once more');
        await _releaseEngine();
        // The native teardown outlives the future that starts it; re-initialising
        // on top of a release still in flight is the state this is escaping.
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  Future<void> _attemptChannel(String channel) async {
    // Anything left over from a previous attempt has to go before `initialize`:
    // the native engine is a process-wide singleton, and standing a second one up
    // on top of the first is how a retry ends up worse off than the failure it was
    // retrying.
    _step = 'teardown';
    await _releaseEngine();

    _step = 'token';
    _log('requesting an audience token…');
    final grant = await _live.audienceToken(channel);
    _log('token granted — appId ${_fingerprint(grant.appId)}, '
        'uid ${grant.uid}, token ${grant.token.length} chars');

    _step = 'initialize';
    final engine = createAgoraRtcEngine();
    await engine.initialize(
      RtcEngineContext(
        appId: grant.appId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ),
    );
    _log('engine initialised');
    _engine = engine;

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            _log('joined "${connection.channelId}" as uid '
                '${connection.localUid} in ${elapsed}ms');
            _joinTimeout?.cancel();
            _joinTimeout = null;
            // The uid the server actually admitted us as. Normally the one we
            // asked for, but it is what every remote canvas is keyed against, so
            // it is taken from the SDK rather than assumed.
            if (connection.localUid != null && connection.localUid != 0) {
              _myAgoraUid = connection.localUid;
            }
            _connection = LiveConnection.joined;
            _error = null;
            notifyListeners();
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            _log('remote $remoteUid joined');
            _remotes[remoteUid] =
                _remotes[remoteUid] ?? RemoteFeed(agoraUid: remoteUid);
            notifyListeners();
          },
          onUserOffline: (connection, remoteUid, reason) {
            _log('remote $remoteUid left (${reason.name})');
            _remotes.remove(remoteUid);
            notifyListeners();
          },
          onRemoteVideoStateChanged: (
            connection,
            remoteUid,
            state,
            reason,
            elapsed,
          ) {
            // A frozen stream is still a stream — usually a couple of seconds of
            // bad signal. Treating it as "no video" would pull the tutor off the
            // screen and replace them with "camera is off" every time the
            // network hiccuped, which on a Nigerian mobile connection is often.
            final publishing = switch (state) {
              RemoteVideoState.remoteVideoStateStopped ||
              RemoteVideoState.remoteVideoStateFailed =>
                false,
              _ => true,
            };
            _setRemoteVideo(
              remoteUid,
              publishing,
              'state ${state.name}/${reason.name}',
            );
          },
          // A decoded frame is proof, where the state callback is only a claim.
          // On a weak connection the state change can be missed or arrive before
          // the subscription settles, which left the room saying "your tutor's
          // camera is off" over a stream that was in fact already arriving.
          onFirstRemoteVideoFrame: (
            connection,
            remoteUid,
            width,
            height,
            elapsed,
          ) =>
              _setRemoteVideo(remoteUid, true, 'first frame ${width}x$height'),
          // The last safety net, for when both callbacks above went missing.
          //
          // Only when frames are genuinely arriving, though: these are reported
          // for a remote whose camera is off too, and taking one as proof of a
          // picture put an empty tile on the stage — a black rectangle where the
          // honest "your tutor's camera is off" belonged. A renderer running at
          // some frame rate, or bytes actually being received, is the difference.
          onRemoteVideoStats: (connection, stats) {
            final uid = stats.uid;
            if (uid == null) return;
            final arriving = (stats.rendererOutputFrameRate ?? 0) > 0 ||
                (stats.decoderOutputFrameRate ?? 0) > 0 ||
                (stats.receivedBitrate ?? 0) > 0;
            if (!arriving) return;
            _setRemoteVideo(
              uid,
              true,
              'stats ${stats.width}x${stats.height} '
                  '@${stats.rendererOutputFrameRate}fps',
            );
          },
          onRemoteAudioStateChanged: (
            connection,
            remoteUid,
            state,
            reason,
            elapsed,
          ) {
            final publishing =
                state == RemoteAudioState.remoteAudioStateStarting ||
                    state == RemoteAudioState.remoteAudioStateDecoding;
            final existing =
                _remotes[remoteUid] ?? RemoteFeed(agoraUid: remoteUid);
            if (existing.hasAudio == publishing &&
                _remotes.containsKey(remoteUid)) {
              return;
            }
            _remotes[remoteUid] = existing.copyWith(hasAudio: publishing);
            notifyListeners();
          },
          onAudioVolumeIndication: (
            connection,
            speakers,
            speakerNumber,
            totalVolume,
          ) {
            var changed = false;
            for (final speaker in speakers) {
              final uid = speaker.uid;
              if (uid == null) continue;
              // The same threshold the web uses, so the "speaking" ring lights up
              // at the same point in both.
              final speaking = (speaker.volume ?? 0) > 5;
              // uid 0 in this callback is always us.
              if (uid == 0) {
                if (_selfSpeaking != speaking) {
                  _selfSpeaking = speaking;
                  changed = true;
                }
                continue;
              }
              final existing = _remotes[uid];
              if (existing != null && existing.speaking != speaking) {
                _remotes[uid] = existing.copyWith(speaking: speaking);
                changed = true;
              }
            }
            if (changed) notifyListeners();
          },
          // A token lasts an hour; a class can run longer. Renewing on the
          // warning is the difference between a class that keeps going and one
          // that silently drops everyone at the hour mark.
          onTokenPrivilegeWillExpire: (connection, token) {
            _log('token expiring — renewing');
            _renewToken(channel);
          },
          // The warning was missed — a phone asleep in a pocket gets no
          // callbacks — and the token has already lapsed. Same fix, last chance.
          onRequestToken: (connection) {
            _log('token lapsed — renewing');
            _renewToken(channel);
          },
          // The server refused the promotion to broadcaster after the fact —
          // rare, and never fatal to being in the room. Putting the toggles back
          // down is the honest thing to draw: the student pressed a button and
          // is not, in fact, on air. `_error` is left alone; it belongs to the
          // join, and overwriting it here would blank a working class.
          onClientRoleChangeFailed: (connection, reason, currentRole) {
            _log('role change refused (${reason.name}), '
                'still ${currentRole.name}');
            if (!isBroadcasting) return;
            _microphoneOn = false;
            _cameraOn = false;
            notifyListeners();
          },
          // Where a join actually fails. `onError` fires for plenty of things
          // that are not fatal; this is the SDK saying whether we are in the
          // channel, and why not.
          onConnectionStateChanged: (connection, state, reason) {
            _log('connection ${state.name} (${reason.name})');
            switch (state) {
              case ConnectionStateType.connectionStateConnected:
                _joinTimeout?.cancel();
                _joinTimeout = null;
                _connection = LiveConnection.joined;
                _error = null;
              case ConnectionStateType.connectionStateReconnecting:
                // Only once we were actually in: this state is also passed
                // through on the way to a first connection.
                if (!isInRoom) return;
                _connection = LiveConnection.reconnecting;
              case ConnectionStateType.connectionStateFailed:
                _joinTimeout?.cancel();
                _joinTimeout = null;
                _error = _reasonMessage(reason);
                _errorDetail = 'agora ${reason.name}';
                _connection = LiveConnection.failed;
              default:
                return;
            }
            notifyListeners();
          },
          onError: (code, message) {
            // Most of what arrives here is a warning the class survives — an
            // audio device the SDK retried, a permission a watching student
            // never needed. Failing the join on any of them is what turned a
            // muted microphone into "could not join the class"; only the codes
            // that genuinely mean "you are not in the room" end it.
            if (!_isFatal(code)) {
              _log('warning ${code.name}: $message');
              return;
            }
            _log('fatal ${code.name}: $message');
            if (_connection == LiveConnection.joining) {
              _joinTimeout?.cancel();
              _joinTimeout = null;
              _error = _errorMessage(code, message);
              _errorDetail = 'agora ${code.name}';
              _connection = LiveConnection.failed;
              notifyListeners();
            }
          },
        ),
      );

    _step = 'configure';
    await engine.enableVideo();
    await engine.enableAudioVolumeIndication(
      interval: 400,
      smooth: 3,
      reportVad: false,
    );
    // What this student's own camera will look like to the room when they are
    // invited to speak. Portrait and modest — the class is watched on phones
    // over mobile data, and a 720p uplink from a student is bandwidth nobody
    // in the room gets anything for.
    await engine.setVideoEncoderConfiguration(
      const VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: 480, height: 640),
        frameRate: 15,
        orientationMode: OrientationMode.orientationModeAdaptive,
        degradationPreference: DegradationPreference.maintainFramerate,
      ),
    );
    // Audience by default: a student watches until they choose to speak.
    await engine.setClientRole(role: ClientRoleType.clientRoleAudience);

    _step = 'joinChannel';
    _myAgoraUid = grant.uid;
    _armJoinDeadline();
    await engine.joinChannel(
      token: grant.token,
      channelId: channel,
      uid: grant.uid,
      options: _audienceOptions,
    );

    // After the channel, not before: on Android the audio route belongs to the
    // call, and asking for the loudspeaker while there is no call to route was
    // its own ERR_NOT_READY. Never fatal to a class that has otherwise joined,
    // so it is not allowed to fail the attempt.
    _step = 'audio route';
    try {
      await engine.setEnableSpeakerphone(true);
    } catch (e) {
      _log('speakerphone: $e');
    }
    _step = 'joined';
  }

  /// What a student joins as: watching, and publishing nothing at all.
  static const _audienceOptions = ChannelMediaOptions(
    clientRoleType: ClientRoleType.clientRoleAudience,
    channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    autoSubscribeAudio: true,
    autoSubscribeVideo: true,
    // Nothing goes out until the student turns it on themselves; see
    // [_applyPublishing], which is what actually opens the uplink.
    publishCameraTrack: false,
    publishMicrophoneTrack: false,
  );

  /// Starts (or restarts) the clock on "Joining the class…".
  void _armJoinDeadline() {
    _joinTimeout?.cancel();
    _joinTimeout = Timer(_joinDeadline, () {
      if (_disposed || _connection != LiveConnection.joining) return;
      _log('no answer after ${_joinDeadline.inSeconds}s — giving up');
      _error = 'The class did not answer. Check your connection and try again.';
      _errorDetail = 'timeout after ${_joinDeadline.inSeconds}s';
      _connection = LiveConnection.failed;
      notifyListeners();
    });
  }

  /// A short, safe-to-show identifier for whatever actually went wrong.
  ///
  /// Deliberately not the message again — [_error] already carries that. What
  /// this adds is which side failed, which is the one thing the message never
  /// said: a refusal the server logged, or a request that never got there.
  static String _detail(Object e) => switch (e) {
        ApiException(:final statusCode?) => 'api $statusCode',
        ApiException(isOffline: true) => 'never reached the server',
        ApiException() => 'api error',
        AgoraRtcException() => 'agora ${e.code}',
        _ => e.runtimeType.toString(),
      };

  /// Enough of the Agora app id to tell "wrong project" from "no project",
  /// without printing a credential into a log the student can share.
  static String _fingerprint(String appId) => appId.isEmpty
      ? '(empty)'
      : '${appId.substring(0, appId.length.clamp(0, 6))}… (${appId.length})';

  /// Records whether [remoteUid] is putting a picture out, without waking the
  /// tree up for a repeat of what it already knows.
  ///
  /// [source] is which callback said so — the three of them disagree often
  /// enough that "the stage says the camera is off" is only answerable by
  /// knowing which one was believed.
  void _setRemoteVideo(int remoteUid, bool publishing, String source) {
    final existing = _remotes[remoteUid] ?? RemoteFeed(agoraUid: remoteUid);
    if (existing.hasVideo == publishing && _remotes.containsKey(remoteUid)) {
      return;
    }
    _log('remote $remoteUid video ${publishing ? 'ON' : 'off'} (via $source)');
    _remotes[remoteUid] = existing.copyWith(hasVideo: publishing);
    notifyListeners();
  }

  /// Whether an SDK error means the student is not in the class.
  ///
  /// Everything absent from this list is a warning: the room carries on, and
  /// saying so over a working class helps nobody.
  static bool _isFatal(ErrorCodeType code) => switch (code) {
        ErrorCodeType.errInvalidToken ||
        ErrorCodeType.errTokenExpired ||
        ErrorCodeType.errInvalidChannelName ||
        ErrorCodeType.errInvalidAppId ||
        ErrorCodeType.errJoinChannelRejected ||
        ErrorCodeType.errNotInitialized =>
          true,
        _ => false,
      };

  static String _errorMessage(ErrorCodeType code, String message) =>
      switch (code) {
        ErrorCodeType.errInvalidToken || ErrorCodeType.errTokenExpired =>
          'Your access to this class expired. Tap retry to rejoin.',
        ErrorCodeType.errInvalidChannelName =>
          "This class's room name is not valid — ask your tutor to recreate it.",
        ErrorCodeType.errInvalidAppId =>
          'This class is misconfigured. Please report it to your tutor.',
        _ => 'Could not join the class (${code.name}: $message).',
      };

  /// Tears everything down and joins again, for the Retry button.
  Future<void> retry() async {
    final channel = _channel;
    if (channel == null) {
      _log('retry ignored — no channel to go back to');
      return;
    }
    _log('retry requested for "$channel"');
    await leave();
    await join(channel);
  }

  /// Fetches a fresh token and hands it to the SDK.
  Future<void> _renewToken(String channel) async {
    try {
      final fresh = await _live.audienceToken(channel);
      await _engine?.renewToken(fresh.token);
      _log('token renewed');
    } catch (e) {
      _log('token renewal failed: $e');
      // The session survives until the token actually lapses, at which point
      // `onConnectionStateChanged` says so and the student can rejoin.
    }
  }

  /// Why the SDK gave up, in words a student can act on.
  static String _reasonMessage(ConnectionChangedReasonType reason) =>
      switch (reason) {
        ConnectionChangedReasonType.connectionChangedInvalidToken ||
        ConnectionChangedReasonType.connectionChangedTokenExpired =>
          'Your access to this class expired. Tap retry to rejoin.',
        ConnectionChangedReasonType.connectionChangedBannedByServer =>
          'You have been removed from this class.',
        ConnectionChangedReasonType.connectionChangedRejectedByServer =>
          'The class refused the connection. Ask your tutor to check the room.',
        ConnectionChangedReasonType.connectionChangedInvalidChannelName =>
          "This class's room name is not valid — ask your tutor to recreate it.",
        ConnectionChangedReasonType.connectionChangedInvalidAppId =>
          'This class is misconfigured. Please report it to your tutor.',
        _ => 'Lost connection to the class. Check your network and try again.',
      };

  /// The microphone, asked for before the class starts.
  ///
  /// Never throws: on a device that refuses to answer at all, joining as a
  /// listener is still better than not joining.
  Future<bool> _requestMicrophonePermission() async {
    try {
      return (await Permission.microphone.request()).isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Asks for microphone (and optionally camera) access.
  ///
  /// Returns false when the student declined, so the caller can say why the
  /// feature didn't turn on rather than failing silently.
  Future<bool> requestSpeakingPermissions({bool camera = false}) async {
    final wanted = [Permission.microphone, if (camera) Permission.camera];
    final results = await wanted.request();
    final granted = results.values.every((status) => status.isGranted);
    if (granted) _canPublish = true;
    return granted;
  }

  /// Whether this student could speak if they chose to.
  bool get canPublish => _canPublish;

  // ─── Taking part ───────────────────────────────────────────────────────────

  /// Opens or closes this student's uplink to match [_microphoneOn] and
  /// [_cameraOn].
  ///
  /// This is the step that actually makes the room hear and see them. Promoting
  /// to broadcaster on its own never did: the publish flags were fixed at join
  /// time and nothing revisited them, so a student could hold the microphone
  /// button down all class and send precisely nothing.
  Future<void> _applyPublishing() async {
    final engine = _engine;
    if (engine == null || !isInRoom) return;
    await engine.updateChannelMediaOptions(
      ChannelMediaOptions(
        clientRoleType: isBroadcasting
            ? ClientRoleType.clientRoleBroadcaster
            : ClientRoleType.clientRoleAudience,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        publishMicrophoneTrack: _microphoneOn,
        publishCameraTrack: _cameraOn,
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
      ),
    );
  }

  /// Turns this student's microphone on or off.
  ///
  /// Switching it on promotes them to a broadcaster in the channel, which is what
  /// lets the room hear them. The tutor still controls whether they *should* be
  /// speaking; this is the student's own mute button.
  Future<bool> setMicrophone(bool on) async {
    final engine = _engine;
    if (engine == null || !isInRoom) return false;

    if (on && !await requestSpeakingPermissions()) return false;

    try {
      if (on) {
        await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
        await engine.enableLocalAudio(true);
        await engine.muteLocalAudioStream(false);
        _microphoneOn = true;
        await _applyPublishing();
      } else {
        _microphoneOn = false;
        // Stop publishing before standing the device down, so the room hears
        // the mute immediately rather than a last half-second of the room.
        await _applyPublishing();
        await engine.muteLocalAudioStream(true);
        await engine.enableLocalAudio(false);
        // Back to audience unless the camera is still up, which would need the
        // broadcaster role to keep publishing.
        if (!_cameraOn) {
          await engine.setClientRole(role: ClientRoleType.clientRoleAudience);
        }
      }
      notifyListeners();
      return true;
    } catch (_) {
      _microphoneOn = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> setCamera(bool on) async {
    final engine = _engine;
    if (engine == null || !isInRoom) return false;

    if (on && !await requestSpeakingPermissions(camera: true)) return false;

    try {
      if (on) {
        await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
        await engine.enableLocalVideo(true);
        await engine.muteLocalVideoStream(false);
        await engine.startPreview();
        _cameraOn = true;
        await _applyPublishing();
      } else {
        _cameraOn = false;
        await _applyPublishing();
        await engine.muteLocalVideoStream(true);
        await engine.stopPreview();
        await engine.enableLocalVideo(false);
        if (!_microphoneOn) {
          await engine.setClientRole(role: ClientRoleType.clientRoleAudience);
        }
      }
      notifyListeners();
      return true;
    } catch (_) {
      _cameraOn = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> switchCamera() async {
    if (!_cameraOn) return;
    try {
      await _engine?.switchCamera();
      _frontCamera = !_frontCamera;
      notifyListeners();
    } catch (_) {/* single-camera device */}
  }

  /// Earpiece or loudspeaker. Loudspeaker by default — a class is not a phone call.
  Future<void> setSpeaker(bool on) async {
    try {
      await _engine?.setEnableSpeakerphone(on);
      _speakerOn = on;
      notifyListeners();
    } catch (_) {/* route unavailable */}
  }

  /// Silences the room without leaving it — for a student who needs to step away.
  Future<void> setRoomMuted(bool muted) async {
    try {
      await _engine?.muteAllRemoteAudioStreams(muted);
    } catch (_) {/* nothing to mute yet */}
  }

  // ─── Leaving ───────────────────────────────────────────────────────────────

  Future<void> leave() async {
    _log('leaving "${_channel ?? '—'}"');
    _joinTimeout?.cancel();
    _joinTimeout = null;

    _remotes.clear();
    _connection = LiveConnection.idle;
    _microphoneOn = false;
    _cameraOn = false;
    _selfSpeaking = false;
    _pinnedAgoraUid = null;
    // Kept, unlike the rest: `retry()` needs to know which room to go back to.
    // `join` overwrites it, and the screen is gone by the time it would matter.
    // Skipped when this is the dispose path: the listeners have already gone
    // with the screen, and notifying a disposed notifier throws.
    if (!_disposed) notifyListeners();

    // Queued behind any join in flight, and ahead of the next one. A room being
    // disposed while its replacement is already opening is the ordinary case
    // when a student taps out and straight back in, and it is the release
    // landing in the middle of the new initialize that leaves the SDK not ready.
    await _serialized(_releaseEngine);
  }

  /// Hands the native engine back.
  ///
  /// Split out from [leave] because a retry has to do this without clearing the
  /// channel it is about to rejoin — and because leaving the engine alive is what
  /// keeps the microphone light on after the screen has closed.
  Future<void> _releaseEngine() async {
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    try {
      await engine.stopPreview();
    } catch (_) {/* preview was never started */}
    try {
      await engine.leaveChannel();
      await engine.release();
    } catch (e) {
      // Already torn down, or the platform channel has gone with the screen.
      _log('engine release: $e');
    }
  }

  /// The channel currently joined, for a reconnect after a network blip.
  String? get channel => _channel;

  @override
  void dispose() {
    // Fire-and-forget: dispose cannot await, and the engine must still be
    // released or the microphone stays held after the screen closes.
    _disposed = true;
    leave();
    super.dispose();
  }
}
