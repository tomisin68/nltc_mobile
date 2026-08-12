import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One topic in the standalone notes reader.
@immutable
class ReaderTopic {
  const ReaderTopic({
    required this.order,
    required this.title,
    required this.file,
  });

  final int order;
  final String title;
  final String file;

  static ReaderTopic? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final order = raw['order'];
    final title = raw['title'];
    final file = raw['file'];
    if (order is! num || title is! String || file is! String) return null;
    if (title.isEmpty || file.isEmpty) return null;
    return ReaderTopic(order: order.toInt(), title: title, file: file);
  }
}

/// Finds the study notes that are published as whole HTML documents rather than
/// as Firestore records.
///
/// Some notes are authored with their own `<style>` block and hand-drawn inline
/// `<svg>` diagrams. The admin editor's sanitiser strips both, so those notes
/// are not in Firestore at all — they are static files on the website, shown by
/// the reader at [baseUrl], which loads each one in an iframe so it keeps its
/// styling and diagrams exactly as written.
///
/// The app shows that reader in a WebView rather than re-drawing the notes
/// natively: they are complete documents whose whole point is that nothing
/// re-renders them. Notes added to the site therefore appear in the app with no
/// release, which is also why the manifest is fetched rather than bundled.
class NotesReaderService {
  /// Trailing slash matters — the topic hash is appended to this.
  static const String baseUrl = 'https://nltc.com.ng/notes-reader/';

  /// The subject the illustrated notes currently cover. Mirrors
  /// `READER_SUBJECT` in the website's `src/utils/notesReader.js`; when a second
  /// subject gets a set, both become a map of subject → folder.
  static const String readerSubject = 'Biology';

  static const Duration _timeout = Duration(seconds: 8);

  /// Held for the life of the process. The manifest is a few kilobytes and
  /// changes when someone deploys the site, so re-reading it per visit buys
  /// nothing. Only success is cached: a fetch that failed offline must be
  /// retried once there is signal again.
  List<ReaderTopic>? _cached;

  /// The published topics, or an empty list if the reader can't be reached.
  ///
  /// Never throws. Study Notes has to keep working on a dead connection, and
  /// with no manifest it simply shows what Firestore holds, as it always did.
  Future<List<ReaderTopic>> manifest() async {
    final cached = _cached;
    if (cached != null) return cached;

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _timeout;
      final request = await client
          .getUrl(Uri.parse('${baseUrl}notes/manifest.json'))
          .timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) return const [];

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      final decoded = json.decode(body);
      if (decoded is! List) return const [];

      final topics = decoded
          .map(ReaderTopic.tryParse)
          .whereType<ReaderTopic>()
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));

      _cached = topics;
      return topics;
    } catch (error) {
      debugPrint('[notes-reader] manifest unavailable: $error');
      return const [];
    } finally {
      client?.close();
    }
  }

  /// The reader URL, optionally deep-linked to one topic.
  ///
  /// `embed=1` tells the reader to drop its own title line, because the
  /// dashboard already draws a header directly above the WebView.
  static String url({int? order, bool embed = true}) {
    final buffer = StringBuffer(baseUrl);
    if (embed) buffer.write('?embed=1');
    if (order != null) {
      buffer.write('#topic-${order.toString().padLeft(2, '0')}');
    }
    return buffer.toString();
  }

  /// The reader entry matching a question-bank topic name, or null.
  static ReaderTopic? find(List<ReaderTopic> topics, String? topicTitle) {
    if (topics.isEmpty) return null;
    final key = _normalise(topicTitle);
    if (key.isEmpty) return null;
    for (final topic in topics) {
      if (_normalise(topic.title) == key) return topic;
    }
    return null;
  }

  /// Topic titles are typed twice — once as a note's `<title>`, once as the
  /// Topic tag on the question bank — so case, punctuation, "&" against "and"
  /// and stray spacing must not stop a match. Kept identical to `normalise()`
  /// in the website's `notesReader.js`.
  static String _normalise(String? title) => (title ?? '')
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim();
}
