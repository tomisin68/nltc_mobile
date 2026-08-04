import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/app_user.dart';

/// Small key/value store for things that must survive a cold start with no
/// network: the chosen theme, whether onboarding has been seen, and a snapshot
/// of the student's profile.
///
/// Anything list-shaped or queryable belongs in [LocalDatabase] instead.
class PrefsService {
  PrefsService(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsService> load() async =>
      PrefsService(await SharedPreferences.getInstance());

  static const _kThemeMode = 'nltc.themeMode';
  static const _kOnboarded = 'nltc.onboarded';
  static const _kProfile = 'nltc.profile';
  static const _kProfileUid = 'nltc.profileUid';
  static const _kLastVerified = 'nltc.lastVerifiedAt';
  static const _kFcmToken = 'nltc.fcmToken';
  static const _kFocusTimer = 'nltc.focusTimer';
  static const _kFocusPreset = 'nltc.focusPreset';

  // ─── Theme ───────────────────────────────────────────────────────────────

  ThemeMode get themeMode => switch (_prefs.getString(_kThemeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_kThemeMode, mode.name);

  // ─── Onboarding ──────────────────────────────────────────────────────────

  bool get hasOnboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded() => _prefs.setBool(_kOnboarded, true);

  // ─── Cached profile ──────────────────────────────────────────────────────

  /// The last known profile, or null if none is cached for [uid].
  ///
  /// Scoped by uid so a second student signing in on the same phone never sees
  /// the first student's cached details.
  AppUser? cachedProfile(String uid) {
    if (_prefs.getString(_kProfileUid) != uid) return null;
    final raw = _prefs.getString(_kProfile);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return AppUser.fromMap(uid, decoded);
    } catch (_) {
      // Corrupt cache — fall back to loading from the network.
    }
    return null;
  }

  Future<void> cacheProfile(AppUser user) async {
    await _prefs.setString(_kProfileUid, user.uid);
    await _prefs.setString(_kProfile, jsonEncode(user.toJson()));
  }

  Future<void> clearProfile() async {
    await _prefs.remove(_kProfile);
    await _prefs.remove(_kProfileUid);
    await _prefs.remove(_kLastVerified);
  }

  // ─── Offline grace window ────────────────────────────────────────────────

  /// When the profile was last confirmed against the server.
  ///
  /// Access expiry is evaluated on-device against the phone's clock, so an
  /// indefinitely-offline device could be kept alive by winding the clock back.
  /// Recording the last real check-in lets the app insist on reconnecting
  /// periodically. See [isWithinOfflineGrace].
  DateTime? get lastVerifiedAt {
    final ms = _prefs.getInt(_kLastVerified);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markVerifiedNow() =>
      _prefs.setInt(_kLastVerified, DateTime.now().millisecondsSinceEpoch);

  /// How long the app trusts a cached profile without seeing the server.
  static const offlineGrace = Duration(days: 7);

  bool get isWithinOfflineGrace {
    final last = lastVerifiedAt;
    // Never verified — treat as within grace so a first run offline isn't a
    // dead end; the profile cache will be empty anyway.
    if (last == null) return true;
    final elapsed = DateTime.now().difference(last);
    // A negative elapsed means the clock moved backwards; treat that as
    // suspicious rather than as infinite grace.
    if (elapsed.isNegative) return false;
    return elapsed <= offlineGrace;
  }

  // ─── Push token ──────────────────────────────────────────────────────────

  String? get fcmToken => _prefs.getString(_kFcmToken);
  Future<void> setFcmToken(String token) => _prefs.setString(_kFcmToken, token);

  // ─── Focus timer ─────────────────────────────────────────────────────────

  /// The in-progress focus session, in the same shape the web keeps under
  /// `nltc_focus_timer`: `{dur, end}` while running, `{dur, left}` while paused.
  ///
  /// Stored as wall-clock end time rather than a remaining count, so a session
  /// keeps ticking while the app is backgrounded and gets no timer callbacks.
  Map<String, dynamic>? get focusSession {
    final raw = _prefs.getString(_kFocusTimer);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Corrupt entry — behave as if no session was saved.
    }
    return null;
  }

  Future<void> setFocusSession(Map<String, dynamic>? session) =>
      session == null
          ? _prefs.remove(_kFocusTimer)
          : _prefs.setString(_kFocusTimer, jsonEncode(session));

  /// How long the student last set a focus block to, in minutes.
  ///
  /// Remembered because a block length is a habit, not a per-session decision —
  /// someone who works in 45-minute blocks should not have to say so every time.
  int get focusPreset => _prefs.getInt(_kFocusPreset) ?? 25;

  Future<void> setFocusPreset(int minutes) =>
      _prefs.setInt(_kFocusPreset, minutes);
}
