import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// What a link turned out to be — the card shown under a message.
class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
  });

  /// The address that was fetched, after redirects.
  final String url;

  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;

  /// The domain, which is the one thing every card can show — and the thing a
  /// student should read before tapping a link a classmate sent.
  String get host {
    final h = Uri.tryParse(url)?.host ?? '';
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  /// A card with nothing but a bare host is not worth the space it takes.
  bool get isWorthShowing => (title ?? '').isNotEmpty || (imageUrl ?? '').isNotEmpty;

  Map<String, Object?> toJson() => {
        'url': url,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (siteName != null) 'siteName': siteName,
      };

  static LinkPreview? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;
    String? str(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return LinkPreview(
      url: url,
      title: str('title'),
      description: str('description'),
      imageUrl: str('imageUrl'),
      siteName: str('siteName'),
    );
  }
}

/// Reads the Open Graph tags off a link so a message carrying one can show what
/// it points at, the way WhatsApp does.
///
/// Every device does its own fetch and keeps the answer on disk. The alternative
/// — the sender resolving the preview once and storing it on the message — would
/// mean new fields on `/chats/{id}/messages/{id}` and a rules change to allow
/// them, and would let whoever sent the message choose what the card says about
/// where it leads. This way the card always describes the page the reader will
/// actually land on.
///
/// Nothing here is allowed to throw or to block a message from rendering: a
/// preview is decoration, and a link with no card is still a working link.
class LinkPreviewService {
  LinkPreviewService(this._prefs);

  final SharedPreferences _prefs;

  static const _cacheKey = 'nltc.linkPreviews';

  /// A page's title and picture change rarely; a week is long enough to make
  /// scrolling back through a conversation free.
  static const _ttl = Duration(days: 7);

  /// Failures expire sooner — a site that was down at lunchtime should get
  /// another chance in the evening.
  static const _failureTtl = Duration(hours: 6);

  /// How many links are remembered. Small enough that the whole map can be
  /// rewritten on each store without being felt.
  static const _maxEntries = 120;

  /// Enough of the document to hold its `<head>`. Reading further would mean
  /// downloading whole pages over a student's data plan for a thumbnail.
  static const _maxBytes = 96 * 1024;

  static const _timeout = Duration(seconds: 8);

  final Map<String, _Entry> _memory = {};
  final Map<String, Future<LinkPreview?>> _inFlight = {};

  /// The preview for [url], from cache if it is there and fresh.
  ///
  /// Returns null when the link has no preview worth showing, when the fetch
  /// failed, or when the URL is not something that can be fetched at all.
  Future<LinkPreview?> preview(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    final key = url;

    final cached = _memory[key] ?? _readDisk(key);
    if (cached != null && !cached.isStale) {
      _memory[key] = cached;
      return cached.preview;
    }

    // Two bubbles quoting the same link must not fetch it twice.
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _fetchAndStore(key, uri);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// The cached preview for [url] with no network call — what a bubble can paint
  /// on its very first frame, before its fetch has been scheduled.
  LinkPreview? cachedPreview(String url) {
    final entry = _memory[url] ?? _readDisk(url);
    return entry != null && !entry.isStale ? entry.preview : null;
  }

  Future<LinkPreview?> _fetchAndStore(String key, Uri uri) async {
    LinkPreview? preview;
    try {
      preview = await _fetch(uri).timeout(_timeout);
    } catch (_) {
      // Offline, timed out, TLS refused, malformed HTML — all the same to a
      // card that simply will not appear.
      preview = null;
    }
    final entry = _Entry(
      preview: preview,
      expiresAt: DateTime.now()
          .add(preview == null ? _failureTtl : _ttl)
          .millisecondsSinceEpoch,
    );
    _memory[key] = entry;
    unawaited(_writeDisk(key, entry));
    return preview;
  }

  Future<LinkPreview?> _fetch(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      // A page that redirects more than this is not worth a thumbnail.
      ..maxConnectionsPerHost = 4;
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.maxRedirects = 5;
      // Some sites serve a different — or no — head to an unknown agent.
      request.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (compatible; NLTCApp/1.0; +https://nltc.com.ng)');
      request.headers.set(HttpHeaders.acceptHeader, 'text/html,*/*;q=0.8');

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }
      // A PDF or an image has no Open Graph tags to read.
      final type = response.headers.contentType?.mimeType ?? '';
      if (!type.contains('html') && type.isNotEmpty) {
        await response.drain<void>();
        return null;
      }

      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length >= _maxBytes) break;
      }
      // `allowMalformed`: a page cut off mid-character must not throw, and a
      // page in an eight-bit charset should still yield its ASCII tags.
      final html = utf8.decode(bytes, allowMalformed: true);
      // `response.redirects` is empty when nothing redirected, in which case the
      // URL asked for is the URL landed on.
      final landed = response.redirects.isEmpty
          ? uri
          : (response.redirects.last.location.hasAuthority
              ? response.redirects.last.location
              : uri.resolveUri(response.redirects.last.location));

      return parseHtml(html, landed);
    } finally {
      client.close(force: true);
    }
  }

  /// Pulls the card out of a page's `<head>`.
  ///
  /// Open Graph first, then Twitter's equivalents, then the plain `<title>` and
  /// `<meta name="description">` — the same order and the same fallbacks every
  /// other link unfurler uses, so a page that previews anywhere previews here.
  @visibleForTesting
  static LinkPreview? parseHtml(String html, Uri uri) {
    final tags = _metaTags(html);

    String? meta(List<String> keys) {
      for (final key in keys) {
        final value = tags[key.toLowerCase()];
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final title = meta(['og:title', 'twitter:title']) ??
        _unescape(
          RegExp(r'<title[^>]*>([\s\S]*?)<\/title>', caseSensitive: false)
                  .firstMatch(html)
                  ?.group(1)
                  ?.trim() ??
              '',
        );

    final image = meta(['og:image', 'og:image:url', 'twitter:image']);

    final preview = LinkPreview(
      url: (meta(['og:url']) ?? uri.toString()),
      title: title.isEmpty ? null : _clip(title, 120),
      description: _clipOrNull(
        meta(['og:description', 'twitter:description', 'description']),
        180,
      ),
      // A relative `og:image` is legal and common; resolve it against the page.
      imageUrl: image == null ? null : uri.resolve(image).toString(),
      siteName: _clipOrNull(meta(['og:site_name']), 60),
    );
    return preview.isWorthShowing ? preview : null;
  }

  /// Every `<meta>` in the document, keyed by its `property` or `name`.
  ///
  /// One pass over the tags rather than a pattern per key we want, because the
  /// pattern has to understand quoting to be right at all: an `og:title` of
  /// `Nigeria's #1 …` is perfectly legal inside double quotes, and a pattern
  /// that stops at either quote mark cuts the title off at the apostrophe.
  static Map<String, String> _metaTags(String html) {
    final tags = <String, String>{};
    // A tag ends at the first `>` that is not inside a quoted value — `>` is
    // legal inside one, and a description is exactly where it turns up.
    final tagPattern = RegExp(
      '<meta\\b(?:[^>"\']|"[^"]*"|\'[^\']*\')*>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in tagPattern.allMatches(html)) {
      final tag = match.group(0)!;
      final key = _attr(tag, 'property') ?? _attr(tag, 'name');
      final content = _attr(tag, 'content');
      if (key == null || key.isEmpty || content == null) continue;
      // First wins: a page repeating `og:image` means the first one.
      tags.putIfAbsent(key.toLowerCase(), () => content);
    }
    return tags;
  }

  /// One attribute of one tag, unescaped. Handles both quote marks and the
  /// unquoted form.
  static String? _attr(String tag, String name) {
    final match = RegExp(
      '\\b${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s"\'>]+))',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(tag);
    if (match == null) return null;
    final value = match.group(1) ?? match.group(2) ?? match.group(3);
    return value == null ? null : _unescape(value.trim());
  }

  static String _clip(String value, int limit) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.length > limit
        ? '${collapsed.substring(0, limit).trimRight()}…'
        : collapsed;
  }

  static String? _clipOrNull(String? value, int limit) =>
      value == null || value.trim().isEmpty ? null : _clip(value, limit);

  /// The entities that actually turn up in a title or a description.
  static String _unescape(String value) {
    final named = value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');
    // Numeric forms, decimal and hex: `&#8217;` for a curly apostrophe is the
    // commonest thing in a page title after `&amp;`.
    final numeric = named.replaceAllMapped(
      RegExp(r'&#(x?)([0-9a-fA-F]+);', caseSensitive: false),
      (m) {
        final code = int.tryParse(
          m.group(2)!,
          radix: m.group(1)!.isEmpty ? 10 : 16,
        );
        return code == null || code < 32 || code > 0x10FFFF
            ? m.group(0)!
            : String.fromCharCode(code);
      },
    );
    // `&amp;` last, so `&amp;lt;` reads back as the text `&lt;` and not as `<`.
    return numeric.replaceAll('&amp;', '&');
  }

  // ─── Disk ──────────────────────────────────────────────────────────────────
  //
  // One preferences key holding every entry, rather than a key each: it keeps
  // the store bounded without having to track which keys exist.

  Map<String, dynamic> _readAll() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  _Entry? _readDisk(String key) {
    final entry = _Entry.fromJson(_readAll()[key]);
    if (entry == null) return null;
    // Warm memory so the next bubble asking skips the JSON decode.
    _memory[key] = entry;
    return entry;
  }

  Future<void> _writeDisk(String key, _Entry entry) async {
    try {
      final all = _readAll()..[key] = entry.toJson();
      if (all.length > _maxEntries) {
        // Drop whatever expires soonest — for equal TTLs that is the oldest.
        final byExpiry = all.entries.toList()
          ..sort((a, b) => _expiryOf(a.value).compareTo(_expiryOf(b.value)));
        for (final stale in byExpiry.take(all.length - _maxEntries)) {
          all.remove(stale.key);
        }
      }
      await _prefs.setString(_cacheKey, jsonEncode(all));
    } catch (_) {
      // A cache that cannot be written is a slower cache, not an error.
    }
  }

  static int _expiryOf(Object? json) =>
      json is Map && json['expiresAt'] is int ? json['expiresAt'] as int : 0;
}

/// A cached answer, including "this link has no preview" — which is worth
/// remembering, or every scroll past a bare link re-fetches the page.
class _Entry {
  const _Entry({required this.preview, required this.expiresAt});

  final LinkPreview? preview;
  final int expiresAt;

  bool get isStale => DateTime.now().millisecondsSinceEpoch > expiresAt;

  Map<String, Object?> toJson() => {
        'expiresAt': expiresAt,
        if (preview != null) 'preview': preview!.toJson(),
      };

  static _Entry? fromJson(Object? json) {
    if (json is! Map) return null;
    final expiresAt = json['expiresAt'];
    if (expiresAt is! int) return null;
    return _Entry(
      preview: LinkPreview.fromJson(json['preview']),
      expiresAt: expiresAt,
    );
  }
}
