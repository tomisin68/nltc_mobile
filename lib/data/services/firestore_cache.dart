import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Read-through cache in front of Firestore, with a memory layer over a disk
/// layer and a TTL per key.
///
/// Port of `src/utils/firestoreCache.js`. It exists for the same reason there:
/// Firestore bills per document read, and a student flicking between views would
/// otherwise re-read the whole video library every time. The disk layer means a
/// cold start shows content before the network answers.
///
/// Concurrent calls for the same key share one fetch, so two widgets mounting
/// together cannot double-charge the read.
class FirestoreCache {
  FirestoreCache(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'nltc_fc_';

  final Map<String, _Entry> _memory = {};
  final Map<String, Future<dynamic>> _inFlight = {};

  /// Returns the cached value for [key] if it is still fresh, otherwise runs
  /// [fetch] and stores the result for [ttl].
  ///
  /// [decode] converts the JSON that came back off disk into `T`. Without it a
  /// disk hit is skipped — which is the right default for values that aren't
  /// plain JSON, since a wrong cast here would be a crash on a cold start.
  Future<T> read<T>(
    String key,
    Duration ttl,
    Future<T> Function() fetch, {
    T Function(Object? json)? decode,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final cached = _memory[key];
    if (cached != null && cached.expiresAt > now) return cached.value as T;

    if (decode != null) {
      final fromDisk = _readDisk<T>(key, now, decode);
      if (fromDisk != null) {
        // Warm the memory layer so the next read skips the JSON decode.
        _memory[key] = fromDisk;
        return fromDisk.value as T;
      }
    }

    final existing = _inFlight[key];
    if (existing != null) return await existing as T;

    final future = _fetchAndStore(key, ttl, fetch, now);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<T> _fetchAndStore<T>(
    String key,
    Duration ttl,
    Future<T> Function() fetch,
    int now,
  ) async {
    final value = await fetch();
    final expiresAt = now + ttl.inMilliseconds;
    _memory[key] = _Entry(value, expiresAt);

    // Only JSON-shaped values survive to disk. Anything else stays in memory —
    // failing to persist a cache entry is not worth failing the read over.
    try {
      final encoded = jsonEncode({'data': value, 'expiresAt': expiresAt});
      await _prefs.setString('$_prefix$key', encoded);
    } catch (_) {
      // Not encodable, or storage is full.
    }
    return value;
  }

  _Entry? _readDisk<T>(String key, int now, T Function(Object?) decode) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final expiresAt = decoded['expiresAt'];
      if (expiresAt is! num || expiresAt <= now) return null;
      return _Entry(decode(decoded['data']), expiresAt.toInt());
    } catch (_) {
      // Corrupt or shape-changed entry — treat as a miss.
      return null;
    }
  }

  /// Drops [key] from both layers. Call after a write the student should see
  /// reflected immediately — finishing a test, for instance.
  void invalidate(String key) {
    _memory.remove(key);
    _prefs.remove('$_prefix$key');
  }

  /// Drops everything. Used on sign-out, so the next student on a shared phone
  /// cannot read the previous one's results out of the cache.
  Future<void> clear() async {
    _memory.clear();
    for (final key in _prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await _prefs.remove(key);
    }
  }
}

class _Entry {
  const _Entry(this.value, this.expiresAt);
  final dynamic value;
  final int expiresAt;
}

/// TTLs per collection, centralised so views don't invent their own.
///
/// Values mirror `TTL` in `src/utils/firestoreCache.js` — the app and website
/// should feel equally fresh.
abstract final class CacheTtl {
  static const videos = Duration(minutes: 30);
  static const quickTests = Duration(minutes: 15);
  static const mockExams = Duration(minutes: 15);
  static const liveSessions = Duration(minutes: 2);
  static const classes = Duration(hours: 1);
  static const centers = Duration(hours: 1);
  static const userResults = Duration(minutes: 5);
  static const userPayments = Duration(minutes: 10);
  static const notifications = Duration(minutes: 3);

  /// `subjects` uses the video TTL on the web — they change about as rarely.
  static const subjects = Duration(minutes: 30);
}
