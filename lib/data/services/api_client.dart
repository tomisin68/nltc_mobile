import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// One tag over every backend call, so a request that never reached the server
/// can be told apart from one the server refused.
///
/// The paths and status codes only — never the id token, never a request body.
void _log(String message) => debugPrint('[api] $message');

/// Thrown for every failed backend call, with enough shape for a ViewModel to
/// tell "you're offline" apart from "the server said no".
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.isOffline = false});

  final String message;
  final int? statusCode;

  /// True when the request never reached the server — no signal, DNS failure,
  /// or the request timed out.
  final bool isOffline;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Talks to the NLTC backend.
///
/// Mirrors the web app's `useBackendFetch`: every request carries a fresh
/// Firebase ID token, and a 401 triggers exactly one retry with a
/// force-refreshed token — which is what happens when Render's free tier wakes
/// from cold sleep and rejects a token minted before it slept.
class ApiClient {
  ApiClient({
    FirebaseAuth? auth,
    this.baseUrl = 'https://nltc-backend.onrender.com',
  }) : _authOverride = auth;

  final FirebaseAuth? _authOverride;

  /// Resolved on use rather than in the constructor.
  ///
  /// `FirebaseAuth.instance` throws unless `Firebase.initializeApp` has already
  /// run, which made merely *constructing* a client — as a test stub does —
  /// depend on a live Firebase app it never intended to talk to.
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  final String baseUrl;

  /// Render cold starts genuinely take this long, so a shorter timeout would
  /// fail requests that were about to succeed.
  static const _timeout = Duration(seconds: 30);

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(String path, [Object? body]) =>
      _send('POST', path, body: body);

  /// A GET that carries no token, for the handful of routes that take none —
  /// `/settings/fees` and `/health`. Kept separate so an accidental omission of
  /// auth on a protected route can't pass silently.
  Future<Map<String, dynamic>> getPublic(String path) =>
      _send('GET', path, authenticated: false);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    final user = _auth.currentUser;
    if (authenticated && user == null) {
      _log('$method $path refused locally — no signed-in user');
      throw const ApiException('Not signed in', statusCode: 401);
    }

    var uri = Uri.parse('$baseUrl/api$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }

    try {
      _log('$method $path…');
      var res = await _dispatch(method, uri, body, await _idToken(user));

      // Only worth retrying when there is a token to refresh; an unauthenticated
      // route answering 401 is a real rejection, not a stale token.
      if (res.statusCode == 401 && user != null) {
        // Token may have just expired, or the backend woke from cold sleep.
        _log('$method $path → 401, retrying with a refreshed token');
        res = await _dispatch(
          method,
          uri,
          body,
          await _idToken(user, force: true),
        );
      }
      _log('$method $path → ${res.statusCode}');
      return _decode(res);
    } on ApiException {
      // Already carries what the server said; re-wrapping it below would lose it.
      rethrow;
    } on SocketException catch (e) {
      _log('$method $path never left the device: $e');
      throw const ApiException(
        'No internet connection.',
        isOffline: true,
      );
    } on TimeoutException {
      _log('$method $path timed out after ${_timeout.inSeconds}s');
      throw const ApiException(
        'The server took too long to respond. Please try again.',
        isOffline: true,
      );
    } on HandshakeException catch (e) {
      _log('$method $path TLS handshake failed: $e');
      throw const ApiException(
        'Could not reach the server securely.',
        isOffline: true,
      );
    } catch (e) {
      // Everything else — a dropped connection mid-response, a platform-level
      // failure. These used to escape untranslated and surface as whatever
      // generic message the caller had for "some Exception", which is how a
      // request that never left the phone came to read as the class refusing it.
      _log('$method $path failed: ${e.runtimeType}: $e');
      throw ApiException(
        'Could not reach the server (${e.runtimeType}).',
        isOffline: true,
      );
    }
  }

  /// The Firebase id token, or a plain explanation of why there isn't one.
  ///
  /// This runs before a single byte goes to the backend, so a failure here is
  /// invisible in the server's logs — which is exactly the shape of bug it was
  /// hiding: no request, no trace, and a message about the connection.
  Future<String?> _idToken(User? user, {bool force = false}) async {
    if (user == null) return null;
    try {
      return await user.getIdToken(force);
    } on FirebaseAuthException catch (e) {
      _log('id token refused: ${e.code}');
      throw ApiException(
        'Could not verify your sign-in (${e.code}). Try signing out and in again.',
        statusCode: 401,
        isOffline: e.code == 'network-request-failed',
      );
    }
  }

  Future<_RawResponse> _dispatch(
    String method,
    Uri uri,
    Object? body,
    String? token,
  ) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.openUrl(method, uri).timeout(_timeout);
      // Omitted entirely rather than sent as "Bearer null" — the backend's auth
      // middleware treats a malformed header as a failure, not as absent.
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');

      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }

      final res = await req.close().timeout(_timeout);
      final text = await res.transform(utf8.decoder).join().timeout(_timeout);
      return _RawResponse(res.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _decode(_RawResponse res) {
    Map<String, dynamic> data = const {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // Non-JSON body (an HTML error page from the proxy, usually).
      }
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      // The body, trimmed: a rejection is usually one line of JSON, and an HTML
      // error page from the proxy is recognisable from its first few words.
      _log('rejected ${res.statusCode}: '
          '${res.body.substring(0, res.body.length.clamp(0, 300))}');
      throw ApiException(
        _errorMessage(data) ?? 'Request failed (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    return data;
  }

  /// The most specific thing the backend said.
  ///
  /// A rejected request answers `{error: 'Validation failed', fields: [...]}`,
  /// and only `fields` says which one and why — "Validation failed" on its own
  /// is indistinguishable from every other kind of no.
  static String? _errorMessage(Map<String, dynamic> data) {
    final detail = data['fields'];
    if (detail is List && detail.isNotEmpty) {
      final reasons = [
        for (final entry in detail)
          if (entry is Map && entry['message'] != null)
            entry['message'].toString(),
      ];
      if (reasons.isNotEmpty) return reasons.join(' ');
    }
    return data['error']?.toString() ?? data['message']?.toString();
  }
}

class _RawResponse {
  const _RawResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
