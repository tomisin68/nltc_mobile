import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/app_user.dart';
import '../services/prefs_service.dart';

/// Auth failure with a message already fit to show a student.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => 'AuthFailure($code): $message';
}

/// Owns "who is signed in" and "what does their profile say".
///
/// Sign-in is one-time by design: Firebase Auth persists the session in
/// platform storage, so [FirebaseAuth.currentUser] survives app restarts and is
/// readable with no network. The profile is cached alongside it, which is what
/// lets a cold start with no signal still render the right screen instead of a
/// spinner or a false paywall.
class AuthRepository {
  AuthRepository({
    required PrefsService prefs,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _prefs = prefs,
        _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final PrefsService _prefs;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  /// Length of the free trial granted on signup — matches the web app.
  static const trialDuration = Duration(days: 3);

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  // ─── Session ─────────────────────────────────────────────────────────────

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user == null) throw const AuthFailure('Sign in failed.');
      return await loadProfile(user.uid, forceRefresh: true) ??
          AppUser(uid: user.uid, email: user.email);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e), code: e.code);
    }
  }

  /// Creates the account and its profile document.
  ///
  /// `studentMode` is hardcoded to `'online'`: the app has no physical-centre
  /// signup path, so no student created here should ever land in the
  /// centre-managed cohort.
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    String? targetExam,
    String? state,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user == null) throw const AuthFailure('Could not create account.');

      await user.updateDisplayName('${firstName.trim()} ${lastName.trim()}');

      final trialEnds = DateTime.now().add(trialDuration);
      // Field names and shape must match the web's `saveUser()` — the same
      // document is read by the dashboard, admin panel and expiry job.
      // `uid` and `email` are mandatory: firestore.rules `validNewUser()`
      // rejects the write without them.
      final data = <String, dynamic>{
        'uid': user.uid,
        'email': email.trim(),
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'phone': phone.trim(),
        'targetExam': targetExam ?? 'JAMB',
        'state': state ?? 'Lagos',
        'studentMode': 'online',
        'center': '',
        'role': 'student',
        'plan': 'free',
        'xp': 0,
        'streak': 0,
        'trialEndsAt': Timestamp.fromDate(trialEnds),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _userDoc(user.uid).set(data);

      final profile = AppUser.fromMap(user.uid, {
        ...data,
        'trialEndsAt': trialEnds.millisecondsSinceEpoch,
      });
      await _prefs.cacheProfile(profile);
      await _prefs.markVerifiedNow();
      return profile;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e), code: e.code);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e), code: e.code);
    }
  }

  Future<void> signOut() async {
    await _prefs.clearProfile();
    await _auth.signOut();
  }

  // ─── Profile ─────────────────────────────────────────────────────────────

  /// Returns the student's profile, preferring speed over freshness.
  ///
  /// Unless [forceRefresh] is set, the cached copy is returned immediately when
  /// one exists — the caller can then call again with [forceRefresh] to update
  /// in the background. A network failure never clears a cached profile;
  /// losing signal must not look like losing your subscription.
  Future<AppUser?> loadProfile(String uid, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _prefs.cachedProfile(uid);
      if (cached != null) return cached;
    }

    try {
      final snap = await _userDoc(uid).get();
      if (!snap.exists) return _prefs.cachedProfile(uid);

      final profile = AppUser.fromMap(uid, snap.data() ?? const {});
      await _prefs.cacheProfile(profile);
      // Only a real server read counts as a check-in; a cache hit doesn't
      // extend the offline grace window.
      if (!snap.metadata.isFromCache) await _prefs.markVerifiedNow();
      return profile;
    } catch (_) {
      // Offline, or rules rejected the read — fall back to what we know.
      return _prefs.cachedProfile(uid);
    }
  }

  /// Live profile updates, seeded from cache so the first frame has data.
  ///
  /// Firestore serves this from its local cache while offline and replays the
  /// server copy on reconnect, so the paywall reacts the moment a payment
  /// lands without the student pulling to refresh.
  Stream<AppUser?> watchProfile(String uid) => _userDoc(uid).snapshots().map(
        (snap) {
          if (!snap.exists) return null;
          final profile = AppUser.fromMap(uid, snap.data() ?? const {});
          // Fire-and-forget: keeping the disk cache warm shouldn't block or
          // fail the stream.
          unawaited(_prefs.cacheProfile(profile));
          if (!snap.metadata.isFromCache) {
            unawaited(_prefs.markVerifiedNow());
          }
          return profile;
        },
      );

  /// Updates the safe, self-editable profile fields.
  ///
  /// Anything outside `validProfileUpdate()` in firestore.rules is rejected by
  /// the server, so callers must stick to profile fields — never `plan`, `xp`
  /// or `role`.
  Future<void> updateProfile(String uid, Map<String, dynamic> patch) async {
    await _userDoc(uid).update({
      ...patch,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String _messageFor(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'That email address does not look right.',
        'user-disabled' => 'This account has been disabled. Contact support.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Email or password is incorrect.',
        'email-already-in-use' =>
          'An account with this email already exists. Try signing in.',
        'weak-password' => 'Choose a password with at least 6 characters.',
        'too-many-requests' =>
          'Too many attempts. Wait a moment and try again.',
        'network-request-failed' =>
          'No internet connection. Check your network and try again.',
        'operation-not-allowed' =>
          'Email sign-in is not enabled. Contact support.',
        _ => e.message ?? 'Something went wrong. Please try again.',
      };
}
