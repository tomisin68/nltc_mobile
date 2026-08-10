import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/question_repository.dart';
import '../../../data/services/local_database.dart';

/// A subject as the practice screen sees it: its name, and whether its bank is
/// already sitting on the device.
class SubjectEntry {
  const SubjectEntry({required this.name, this.pack});

  final String name;
  final SubjectPack? pack;

  bool get isDownloaded => pack != null && pack!.questionCount > 0;
  int get questionCount => pack?.questionCount ?? 0;
  bool get isStale => pack?.isStale ?? false;
}

/// Drives the practice tab: the subject catalogue and the download queue.
class PracticeController extends ChangeNotifier {
  PracticeController(this._questions);

  final QuestionRepository _questions;

  List<String> _catalogue = const [];
  Map<String, SubjectPack> _packs = const {};
  bool _loading = true;
  String? _error;
  String _query = '';

  /// The subject being pulled down right now, if any. One at a time — parallel
  /// downloads on a Nigerian mobile connection just make them all slow.
  String? _downloading;
  int _downloadedSoFar = 0;
  int? _downloadTotal;
  double? _downloadFraction;
  StreamSubscription<DownloadProgress>? _downloadSub;

  bool get isLoading => _loading;
  String? get error => _error;
  String get query => _query;
  String? get downloadingSubject => _downloading;
  int get downloadedSoFar => _downloadedSoFar;

  /// How many the bank holds, when the server said. Null leaves the strip on an
  /// indeterminate bar rather than an invented one.
  int? get downloadTotal => _downloadTotal;
  double? get downloadFraction => _downloadFraction;

  bool isDownloading(String subject) => _downloading == subject;

  /// Subjects that are usable offline, newest download first — this is what the
  /// home screen offers as "jump back in".
  List<SubjectEntry> get downloaded {
    final entries = _packs.values
        .where((p) => p.questionCount > 0)
        .map((p) => SubjectEntry(name: p.subject, pack: p))
        .toList()
      ..sort((a, b) => b.pack!.downloadedAt.compareTo(a.pack!.downloadedAt));
    return entries;
  }

  /// The full catalogue, filtered by the search box, downloaded subjects first.
  List<SubjectEntry> get visible {
    final needle = _query.trim().toLowerCase();
    final names = {..._catalogue, ..._packs.keys}.toList()..sort();

    final entries = names
        .where((n) => needle.isEmpty || n.toLowerCase().contains(needle))
        .map((n) => SubjectEntry(name: n, pack: _packs[n]))
        .toList();

    entries.sort((a, b) {
      if (a.isDownloaded != b.isDownloaded) return a.isDownloaded ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// The entry for one subject by name, whether or not it has been downloaded.
  ///
  /// Used when something outside the practice tab already knows which subject it
  /// wants — a study note's "test this topic" button, for instance. An
  /// un-downloaded subject still gets an entry, because the setup sheet is where
  /// the download is offered.
  SubjectEntry entryFor(String subject) =>
      SubjectEntry(name: subject, pack: _packs[subject]);

  void search(String value) {
    if (value == _query) return;
    _query = value;
    notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _questions.subjects(),
        _questions.downloadedPacks(),
      ]);
      _catalogue = results[0] as List<String>;
      _packs = {
        for (final pack in results[1] as List<SubjectPack>) pack.subject: pack,
      };
    } catch (_) {
      _error = 'Could not load subjects. Check your connection and try again.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Refreshes only the pack table — cheap enough to call after every download
  /// or delete without re-hitting Firestore for the catalogue.
  Future<void> _reloadPacks() async {
    final packs = await _questions.downloadedPacks();
    _packs = {for (final pack in packs) pack.subject: pack};
    notifyListeners();
  }

  /// Pulls a subject's bank onto the device, reporting progress as it pages.
  ///
  /// Returns the number of questions saved, or null if it failed — the caller
  /// owns telling the student, since only it knows which surface to say it on.
  Future<int?> download(String subject) async {
    if (_downloading != null) return null;

    _downloading = subject;
    _downloadedSoFar = 0;
    _downloadTotal = null;
    _downloadFraction = null;
    _error = null;
    notifyListeners();

    final completer = Completer<int?>();
    _downloadSub = _questions.downloadSubject(subject).listen(
      (progress) {
        _downloadedSoFar = progress.fetched;
        _downloadTotal = progress.total;
        _downloadFraction = progress.fraction;
        notifyListeners();
      },
      onError: (_) {
        _downloading = null;
        notifyListeners();
        if (!completer.isCompleted) completer.complete(null);
      },
      onDone: () async {
        final saved = _downloadedSoFar;
        _downloading = null;
        await _reloadPacks();
        if (!completer.isCompleted) completer.complete(saved);
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  Future<void> delete(String subject) async {
    await _questions.deletePack(subject);
    await _reloadPacks();
  }

  Future<List<String>> topicsFor(String subject) =>
      _questions.topicsFor(subject);

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }
}
