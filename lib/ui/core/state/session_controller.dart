import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/firestore_cache.dart';
import '../../../data/services/local_database.dart';
import '../../../domain/models/access_state.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/xp_result.dart';

enum SessionStatus {
  /// Firebase hasn't reported yet. Lasts a frame or two on a warm start.
  unknown,
  signedOut,
  signedIn,
}

/// The one place the UI asks "who is signed in, and are they allowed in?".
///
/// Sits on top of [AuthRepository]: it follows `authStateChanges`, then holds a
/// live subscription to that student's profile so a payment landing on the
/// website unlocks the app without a restart. The cached profile is read first
/// so the first signed-in frame already has a name and an access state, even
/// with no signal.
class SessionController extends ChangeNotifier {
  SessionController({
    required AuthRepository auth,
    required LocalDatabase local,
    required FirestoreCache cache,
  })  : _auth = auth,
        _local = local,
        _cache = cache {
    _authSub = _auth.authStateChanges.listen(_onAuthChanged);
  }

  final AuthRepository _auth;
  final LocalDatabase _local;
  final FirestoreCache _cache;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _profileSub;
  Timer? _accessTimer;

  SessionStatus _status = SessionStatus.unknown;
  User? _account;
  AppUser? _profile;
  AccessState _access = AccessState.evaluate(null);

  SessionStatus get status => _status;

  /// The Firebase account. [profile] is the Firestore document beside it.
  User? get account => _account;
  AppUser? get profile => _profile;

  /// Whether this student has proved they own their email address.
  ///
  /// Two sources, because either can be the only one carrying the answer: the
  /// profile document is what the app reads offline and what the website's
  /// admin panel reports, while the Firebase Auth record is what a token
  /// carries and survives a profile read being refused. The backend sets both
  /// together, so disagreement only ever means one of them hasn't caught up.
  ///
  /// [_justVerified] covers the seconds after a successful code entry, before
  /// either source has been re-read — long enough for the banner to reappear
  /// under a student who has just dismissed it by verifying.
  bool get emailVerified =>
      _justVerified ||
      (_profile?.emailVerified ?? false) ||
      (_account?.emailVerified ?? false);

  bool _justVerified = false;

  /// Records that the backend has accepted this student's code.
  ///
  /// Only ever called after a 200 from `/auth/verify-otp`, so this cannot be
  /// used to claim a verification that didn't happen. It then pulls both real
  /// sources up to date and lets the local flag go.
  Future<void> markEmailVerified() async {
    _justVerified = true;
    notifyListeners();

    // `reload()` is what refreshes `emailVerified` on the Auth record — the
    // cached User object never learns of a server-side change on its own.
    try {
      await _account?.reload();
      _account = _auth.currentUser;
    } catch (_) {
      // Offline. The profile stream will carry it instead.
    }
    await refreshProfile();
    notifyListeners();
  }

  /// What this student is currently entitled to.
  ///
  /// Held rather than computed per read so every gate in the app sees the same
  /// answer within a frame, and so the controller can tell when it changes and
  /// rebuild the UI itself — a free trial runs out on the clock, with no
  /// profile write to react to.
  AccessState get access => _access;

  /// The longest the app will go without re-checking a live grant.
  ///
  /// A timer set days out does not survive a device sleeping or its clock being
  /// corrected, and the countdown on the dashboard has to tick down anyway, so
  /// long grants are re-checked on this cadence instead of once.
  static const _maxAccessCheckInterval = Duration(hours: 6);

  /// Re-evaluates access against the clock and rebuilds if it moved.
  ///
  /// Call this when the app comes back to the foreground: a phone that slept
  /// through the end of the trial gets no timer callback.
  void recheckAccess() => _applyAccess(notifyOnChange: true);

  void _applyAccess({required bool notifyOnChange}) {
    final next = AccessState.evaluate(_profile);
    final changed = next != _access;
    _access = next;
    _armAccessTimer();
    if (changed && notifyOnChange) notifyListeners();
  }

  /// How long to wait before re-evaluating [access], or null if nothing will
  /// change on its own.
  ///
  /// Only an active grant expires by itself. A locked account cannot unlock
  /// without a payment, and a payment arrives on the profile stream — so there
  /// is nothing to sit and wait for.
  @visibleForTesting
  static Duration? accessCheckDelay(AccessState access, DateTime now) {
    final lapsesAt = access.lapsesAt;
    if (lapsesAt == null) return null;

    // A second past the boundary, so the re-evaluation is unambiguously after
    // it rather than racing it on a coarse clock.
    final remaining = lapsesAt.difference(now) + const Duration(seconds: 1);
    if (remaining.isNegative) return Duration.zero;
    return remaining > _maxAccessCheckInterval
        ? _maxAccessCheckInterval
        : remaining;
  }

  /// Wakes the app up when the current grant lapses.
  void _armAccessTimer() {
    _accessTimer?.cancel();
    _accessTimer = null;

    final delay = accessCheckDelay(_access, DateTime.now());
    if (delay == null) return;
    _accessTimer = Timer(delay, _onAccessTick);
  }

  void _onAccessTick() {
    final wasActive = _access.active;
    _applyAccess(notifyOnChange: true);

    // The grant just ran out. Pull the profile once before settling on locked:
    // a renewal that landed while the stream was offline should let the student
    // straight back in instead of stranding them behind a paywall they paid.
    if (wasActive && !_access.active) unawaited(refreshProfile());
  }

  Future<void> _onAuthChanged(User? user) async {
    _account = user;
    // Belongs to the account that earned it, not to the app.
    _justVerified = false;
    await _profileSub?.cancel();
    _profileSub = null;

    if (user == null) {
      _profile = null;
      _status = SessionStatus.signedOut;
      _applyAccess(notifyOnChange: false);
      notifyListeners();
      return;
    }

    final uid = user.uid;
    final cached = await _auth.loadProfile(uid);
    // A second auth event may have landed while that was in flight — if the
    // account changed underneath us, this result is stale.
    if (_account?.uid != uid) return;

    _profile = cached;
    _status = SessionStatus.signedIn;
    _applyAccess(notifyOnChange: false);
    notifyListeners();

    _profileSub = _auth.watchProfile(uid).listen(
      (profile) {
        // A null here means the document is missing — mid-signup, or deleted.
        // Keep the last known copy rather than blanking the screen.
        if (profile == null || _account?.uid != uid) return;
        _profile = profile;
        _applyAccess(notifyOnChange: false);
        notifyListeners();
      },
      // Offline or a rules rejection: hold what we have. Losing signal must
      // not look like losing your subscription.
      onError: (_) {},
    );
  }

  /// Patches the in-memory profile with XP the backend has just awarded.
  ///
  /// The Firestore stream will deliver the same numbers a moment later, but
  /// "a moment" is long enough for a student who just submitted a test to see an
  /// unchanged XP bar and assume it didn't count. Access is deliberately not
  /// re-evaluated: XP cannot unlock or lock an account, so there is nothing here
  /// that could move the paywall.
  void applyXpResult(XpResult result) {
    final profile = _profile;
    if (profile == null || result.newXp == null) return;

    _profile = profile.copyWithProgress(
      xp: result.newXp,
      streak: result.newStreak,
      cbtCount: result.newCbtCount,
    );
    notifyListeners();
  }

  /// Forces a server read of the profile.
  ///
  /// The live subscription already keeps this current; this is for the student
  /// who has just paid on the website and wants to pull-to-refresh rather than
  /// wait. Failures are swallowed — the cached profile stands.
  Future<void> refreshProfile() async {
    final uid = _account?.uid;
    if (uid == null) return;

    final fresh = await _auth.loadProfile(uid, forceRefresh: true);
    if (fresh == null || _account?.uid != uid) return;
    _profile = fresh;
    _applyAccess(notifyOnChange: false);
    notifyListeners();
  }

  /// Signs out and wipes this student's on-device data, so the next person to
  /// use a shared phone starts clean.
  Future<void> signOut() async {
    await _profileSub?.cancel();
    _profileSub = null;
    await _local.clearUserData();
    // Cached Firestore reads go too. Most keys are uid-scoped, but the memory
    // layer outlives the sign-out, and a shared phone must not let the next
    // student read the previous one's results out of it.
    await _cache.clear();
    await _auth.signOut();
  }

  @override
  void dispose() {
    _accessTimer?.cancel();
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
