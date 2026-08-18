import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/exam_config.dart';
import '../../domain/models/passage_slot.dart';
import '../../domain/models/question.dart';
import '../../domain/models/subject.dart';
import '../services/local_database.dart';
import 'learning_profile_repository.dart';

/// Progress of a subject download, for the UI to show a real bar rather than
/// an indeterminate spinner.
class DownloadProgress {
  const DownloadProgress({
    required this.fetched,
    required this.done,
    this.total,
  });

  final int fetched;

  /// How many the subject's bank holds, or null when the server wouldn't say.
  /// Counted before the download starts, so it is what to measure against — not
  /// what will necessarily be saved, since a malformed question is skipped.
  final int? total;

  final bool done;

  /// How far along, or null when there is no total to be a fraction of.
  double? get fraction {
    final of = total ?? 0;
    if (of <= 0) return null;
    return (fetched / of).clamp(0.0, 1.0);
  }
}

/// Supplies questions, from the device when possible and the network when not.
///
/// Questions are read straight from Firestore rather than through
/// `/api/cbt/questions`, for two reasons: the backend route filters on a
/// `flagged` field the admin uploader never writes (so it returns nothing
/// against real data), and grading has to happen on-device for offline exams
/// to work at all — which means the answer key has to ship with the question.
/// That matches what the web app already does.
class QuestionRepository {
  QuestionRepository({
    required LocalDatabase local,
    FirebaseFirestore? firestore,
  })  : _local = local,
        _db = firestore ?? FirebaseFirestore.instance;

  final LocalDatabase _local;
  final FirebaseFirestore _db;

  /// Firestore caps an `IN` query at 30 values, and reads are billed per
  /// document, so packs are fetched in pages rather than one huge read.
  static const _pageSize = 500;

  // ─── Catalogue ───────────────────────────────────────────────────────────

  /// Subject names available to study.
  ///
  /// Falls back to whatever is already downloaded when the network is gone, so
  /// the subject picker is never empty offline.
  Future<List<String>> subjects() async {
    try {
      final snap = await _db.collection('subjects').orderBy('name').get();
      final names = snap.docs
          .map((d) => (d.data()['name'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.isNotEmpty) return names;
    } catch (_) {
      // Offline — fall through to the downloaded packs.
    }
    final packs = await _local.downloadedPacks();
    return packs.map((p) => p.subject).toList();
  }

  Future<List<SubjectPack>> downloadedPacks() => _local.downloadedPacks();
  Future<SubjectPack?> packFor(String subject) => _local.packFor(subject);
  Future<List<String>> topicsFor(String subject) => _local.topicsFor(subject);
  Future<void> deletePack(String subject) => _local.deleteSubjectPack(subject);

  // ─── Download ────────────────────────────────────────────────────────────

  /// Pulls a subject's whole bank onto the device — every question in it, not a
  /// sample of it. A student who downloads Chemistry for a journey with no signal
  /// gets the same bank the app would have drawn from online.
  ///
  /// Emits progress as it pages so the student can watch it fill on a slow
  /// connection. Each page is written to disk as it lands, so the bank is never
  /// held in memory all at once, and the pack is only committed once the last
  /// page has arrived — an interrupted download leaves the previous pack intact
  /// rather than a half-written one that looks complete.
  Stream<DownloadProgress> downloadSubject(String subject) async* {
    await _local.beginSubjectPack();

    try {
      // Asked for up front so the strip can show a real bar. A count aggregate
      // is billed as one read per thousand documents, which is nothing next to
      // the download itself, and the bar is worth far more now that a bank is
      // no longer capped at a couple of thousand questions.
      final total = await _bankSize(subject);
      yield DownloadProgress(fetched: 0, total: total, done: false);

      var fetched = 0;
      DocumentSnapshot<Map<String, dynamic>>? cursor;

      while (true) {
        var query = _db
            .collection('questions')
            .where('subject', isEqualTo: subject)
            .limit(_pageSize);
        if (cursor != null) query = query.startAfterDocument(cursor);

        // Force a server read: a cache hit here would "download" nothing.
        final snap = await query.get(const GetOptions(source: Source.server));
        if (snap.docs.isEmpty) break;

        final page = <Question>[];
        for (final doc in snap.docs) {
          final q = Question.fromMap(doc.id, doc.data());
          if (q.isUsable) page.add(q);
        }
        fetched = await _local.stageQuestions(page);

        cursor = snap.docs.last;
        yield DownloadProgress(fetched: fetched, total: total, done: false);

        if (snap.docs.length < _pageSize) break;
      }

      if (fetched == 0) {
        // The bank came back empty — usually a subject that was renamed on the
        // server. Committing that would delete a pack the student already has
        // and can still sit exams with, so leave it exactly where it is; the
        // caller says "nothing published yet" and nobody loses anything.
        await _local.discardStagedPack();
        yield DownloadProgress(fetched: 0, total: total, done: true);
        return;
      }

      final saved = await _local.commitSubjectPack(subject);
      yield DownloadProgress(fetched: saved, total: total, done: true);
    } catch (_) {
      // A pack that never finished downloading is not worth keeping around,
      // and the student still has whatever they had before.
      await _local.discardStagedPack();
      rethrow;
    }
  }

  /// How many questions the subject's bank holds, or null if the count could not
  /// be had. A missing total only costs the progress bar its percentage, so it
  /// must never be the reason a download fails to start.
  Future<int?> _bankSize(String subject) async {
    try {
      final snap = await _db
          .collection('questions')
          .where('subject', isEqualTo: subject)
          .count()
          .get();
      return snap.count;
    } catch (_) {
      return null;
    }
  }

  // ─── Drawing an exam ─────────────────────────────────────────────────────

  /// Picks the questions for one subject's worth of a sitting.
  ///
  /// The draw is random every time. Supplying a [profile] does not make it
  /// adaptive — it only tells the draw which questions this student has already
  /// been served, so those are held back until the fresh ones run out. Matches
  /// `drawPaper` on the website, so the two surfaces don't repeat each other.
  ///
  /// [passages] pins whole passages to fixed positions — what a UTME English
  /// paper does with its comprehension and cloze sets. Everything outside those
  /// positions is still drawn independently at random.
  ///
  /// Prefers the downloaded pack: it is instant and works with no signal. Falls
  /// back to Firestore only when the subject hasn't been downloaded, and that
  /// path fails loudly offline rather than starting an exam it can't fill.
  Future<List<Question>> drawExam({
    required String subject,
    required int count,
    String? topic,
    List<String> topics = const [],
    String? examType,
    String bank = seniorBank,
    LearningProfile? profile,
    List<PassageSlot> passages = const [],
  }) async {
    final wantedTopics = <String>{
      if (topic != null && topic.isNotEmpty) topic,
      ...topics.where((t) => t.trim().isNotEmpty),
    }.toList();

    // The junior bank is never downloaded — BECE practice has always read
    // straight from `jssQuestions` — so only the senior path consults the device.
    if (bank == seniorBank) {
      final pack = await _local.packFor(subject);
      if (pack != null && pack.questionCount > 0) {
        final pool = await _local.questionPool(
          subject: subject,
          topics: wantedTopics,
          examType: examType,
        );
        if (pool.isNotEmpty) {
          return _select(pool, count, profile, passages);
        }
      }
    }

    return _drawFromNetwork(
      subject: subject,
      count: count,
      topics: wantedTopics,
      examType: examType,
      bank: bank,
      profile: profile,
      passages: passages,
    );
  }

  /// Draws a whole multi-subject paper, one section per entry in [requests].
  ///
  /// Order is preserved, which is what puts English first in a JAMB paper. A
  /// subject whose bank turns out to be empty is dropped rather than failing the
  /// paper — three subjects is a worse sitting than four, but it is still a
  /// sitting, and this is exactly what the web does with `Promise.allSettled`.
  Future<DrawnPaper> drawPaper(
    List<SectionRequest> requests, {
    String bank = seniorBank,
    LearningProfile? profile,
  }) async {
    final questions = <Question>[];
    final sections = <ExamSection>[];

    for (final request in requests) {
      final drawn = await drawExam(
        subject: request.name,
        count: request.count,
        topics: request.topics,
        bank: bank,
        profile: profile,
        passages: request.passages,
      );
      if (drawn.isEmpty) continue;

      sections.add(
        ExamSection(
          key: request.key,
          name: request.name,
          start: questions.length,
          length: drawn.length,
        ),
      );
      questions.addAll(drawn);
    }

    return DrawnPaper(questions: questions, sections: sections);
  }

  /// Picks the questions for one section, honouring any passage slots.
  ///
  /// With no slots this is the plain random draw every other subject uses.
  List<Question> _select(
    List<Question> pool,
    int count,
    LearningProfile? profile, [
    List<PassageSlot> passages = const [],
  ]) {
    if (passages.isEmpty) return _random(pool, count, profile);
    return assemblePassagePaper(
      pool: pool,
      count: count,
      slots: passages,
      draw: (candidates, n) => _random(candidates, n, profile),
    );
  }

  /// Draws [count] questions at random from a candidate pool.
  List<Question> _random(
    List<Question> pool,
    int count,
    LearningProfile? profile,
  ) {
    if (profile == null) {
      final shuffled = [...pool]..shuffle();
      return shuffled.take(count).toList();
    }
    // With a profile the draw is still random — the profile only says which
    // questions this student has already been served, so those go last.
    return LearningProfileRepository.drawPaper(
      pool,
      profile.seenQuestions,
      count,
    );
  }

  Future<List<Question>> _drawFromNetwork({
    required String subject,
    required int count,
    required List<String> topics,
    required String bank,
    String? examType,
    LearningProfile? profile,
    List<PassageSlot> passages = const [],
  }) async {
    // A single topic filters server-side; several are filtered here, because
    // Firestore's `whereIn` and an inequality on another field can't share a
    // query without a composite index per combination.
    var query = _db.collection(bank).where('subject', isEqualTo: subject);
    if (topics.length == 1) {
      query = query.where('topic', isEqualTo: topics.first);
    }

    // Over-fetch: the draw needs a pool to choose from, and Firestore has no
    // random ordering, so taking the first N every time would serve the same
    // exam repeatedly. The ceiling matches the web's own `limit(500)`.
    final wanted = topics.length > 1 ? _networkPoolCeiling : count * 8;
    final snap = await query
        .limit(wanted.clamp(count, _networkPoolCeiling))
        .get();

    var pool = snap.docs
        .map((d) => Question.fromMap(d.id, d.data()))
        .where((q) => q.isUsable)
        .toList();

    if (topics.length > 1) {
      final wantedTopics = topics.map((t) => t.toLowerCase().trim()).toSet();
      pool = pool
          .where((q) => wantedTopics.contains((q.topic ?? '').toLowerCase().trim()))
          .toList();
    }
    if (examType != null && examType.isNotEmpty) {
      final wantedType = examType.toLowerCase();
      pool = pool
          .where((q) => (q.examType ?? '').toLowerCase() == wantedType)
          .toList();
    }

    // The pool above is capped, and a bank the size of English will not fit
    // inside it — the passage questions would simply never be among the 500
    // that came back. Each slot's topic is fetched on its own, so the passage
    // is drawn from all of them rather than from whichever happened to land.
    if (passages.isNotEmpty) {
      final seen = pool.map((q) => q.id).toSet();
      for (final slot in passages) {
        for (final q in await _passagePool(bank, subject, slot)) {
          if (seen.add(q.id)) pool.add(q);
        }
      }
    }

    return _select(pool, count, profile, passages);
  }

  /// Every question filed under one slot's topic, or nothing when the read
  /// fails — a passage that can't be fetched costs the paper its passage, not
  /// the paper.
  Future<List<Question>> _passagePool(
    String bank,
    String subject,
    PassageSlot slot,
  ) async {
    try {
      final snap = await _db
          .collection(bank)
          .where('subject', isEqualTo: subject)
          .where('topic', isEqualTo: slot.topic)
          .limit(_networkPoolCeiling)
          .get();
      return snap.docs
          .map((d) => Question.fromMap(d.id, d.data()))
          .where((q) => q.isUsable && slot.claims(q))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// The senior question bank. The junior syllabus lives in its own collection
  /// because BECE questions are graded against a different syllabus entirely.
  static const seniorBank = 'questions';
  static const juniorBank = 'jssQuestions';

  /// Matches the web's `limit(500)` — enough pool for adaptive ranking to have a
  /// real choice, without paying for the whole bank on every sitting.
  static const _networkPoolCeiling = 500;

  /// Distinct topics in a subject's bank, on the device or over the network.
  Future<List<String>> examTopicsFor(
    String subject, {
    String bank = seniorBank,
  }) async {
    if (bank == seniorBank) {
      final local = await _local.topicsFor(subject);
      if (local.isNotEmpty) return local;
    }
    try {
      final snap = await _db
          .collection(bank)
          .where('subject', isEqualTo: subject)
          .limit(_networkPoolCeiling * 4)
          .get();
      final topics = snap.docs
          .map((d) => (d.data()['topic'] ?? '').toString().trim())
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      return topics;
    } catch (_) {
      return const [];
    }
  }

  /// Rebuilds the exact questions from a past attempt, in the order shown.
  Future<List<Question>> questionsForReview(List<String> ids) =>
      _local.questionsByIds(ids);
}

/// One subject to draw for a multi-subject paper.
class SectionRequest {
  const SectionRequest({
    required this.key,
    required this.name,
    required this.count,
    this.topics = const [],
    this.passages = const [],
  });

  /// Builds a request from a decorated subject, so the key and display name can
  /// never drift apart.
  SectionRequest.of(
    Subject subject,
    this.count, {
    this.topics = const [],
    this.passages = const [],
  })  : key = subject.key,
        name = subject.name;

  final String key;
  final String name;
  final int count;
  final List<String> topics;

  /// Runs of questions that each have to come from one passage. Empty for
  /// every section but UTME English.
  final List<PassageSlot> passages;
}

/// A drawn paper: the flat question list, and where each subject starts in it.
class DrawnPaper {
  const DrawnPaper({required this.questions, required this.sections});

  final List<Question> questions;
  final List<ExamSection> sections;

  bool get isEmpty => questions.isEmpty;
  int get total => questions.length;
}
