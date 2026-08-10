import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/app_user.dart' show tsToMs;
import '../../domain/models/question.dart';
import '../services/api_client.dart';
import '../services/firestore_cache.dart';

/// How often a question has been served to this student, and when last.
class SeenQuestion {
  const SeenQuestion({required this.seenCount, required this.lastSeenAt});

  final int seenCount;
  final int lastSeenAt;

  static const unseen = SeenQuestion(seenCount: 0, lastSeenAt: 0);

  factory SeenQuestion.fromMap(Map<String, dynamic> m) => SeenQuestion(
        seenCount: m['seenCount'] is num ? (m['seenCount'] as num).toInt() : 0,
        lastSeenAt: tsToMs(m['lastSeenAt']) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'seenCount': seenCount,
        'lastSeenAt': lastSeenAt,
      };
}

/// A topic the engine thinks this student is weak on.
class WeakTopic {
  const WeakTopic({
    required this.subject,
    required this.topic,
    required this.mastery,
  });

  /// The slugified subject key — `further_mathematics`, not the display name.
  final String subject;
  final String topic;

  /// 0..1.
  final double mastery;

  /// `further_mathematics` → `Further Mathematics`, for display.
  String get subjectLabel => subject
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  factory WeakTopic.fromMap(Map<String, dynamic> m) => WeakTopic(
        subject: (m['subject'] ?? '').toString(),
        topic: (m['topic'] ?? '').toString(),
        mastery: m['pMastery'] is num ? (m['pMastery'] as num).toDouble() : 0,
      );

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'topic': topic,
        'pMastery': mastery,
      };
}

/// The student's adaptive-learning profile (`users/{uid}/ml/profile`).
class LearningProfile {
  const LearningProfile({
    this.abilityBySubject = const {},
    this.seenQuestions = const {},
    this.weakTopics = const [],
  });

  /// Elo rating per subject key. 1200 is the neutral starting point.
  final Map<String, double> abilityBySubject;

  final Map<String, SeenQuestion> seenQuestions;
  final List<WeakTopic> weakTopics;

  static const neutralTheta = 1200.0;

  double thetaFor(String subjectKey) =>
      abilityBySubject[subjectKey] ?? neutralTheta;

  factory LearningProfile.fromMap(Map<String, dynamic> m) {
    final ability = <String, double>{};
    final rawAbility = m['abilityBySubject'];
    if (rawAbility is Map) {
      rawAbility.forEach((key, value) {
        final theta = value is Map ? value['theta'] : null;
        if (theta is num) ability[key.toString()] = theta.toDouble();
      });
    }

    final seen = <String, SeenQuestion>{};
    final rawSeen = m['seenQuestions'];
    if (rawSeen is Map) {
      rawSeen.forEach((key, value) {
        if (value is Map) {
          seen[key.toString()] =
              SeenQuestion.fromMap(Map<String, dynamic>.from(value));
        }
      });
    }

    final weak = <WeakTopic>[];
    final rawWeak = m['weakTopics'];
    if (rawWeak is List) {
      for (final row in rawWeak) {
        if (row is Map) {
          weak.add(WeakTopic.fromMap(Map<String, dynamic>.from(row)));
        }
      }
    }

    return LearningProfile(
      abilityBySubject: ability,
      seenQuestions: seen,
      weakTopics: weak,
    );
  }

  Map<String, dynamic> toJson() => {
        'abilityBySubject': {
          for (final entry in abilityBySubject.entries)
            entry.key: {'theta': entry.value},
        },
        'seenQuestions': {
          for (final entry in seenQuestions.entries)
            entry.key: entry.value.toJson(),
        },
        'weakTopics': [for (final t in weakTopics) t.toJson()],
      };
}

/// One answered question, on its way to the learning engine.
class AnswerRecord {
  const AnswerRecord({
    required this.questionId,
    required this.subject,
    required this.correct,
    this.topic,
    this.difficultyLabel,
  });

  final String questionId;

  /// The subject *key*, not the display name — the engine indexes ability by key.
  final String subject;
  final bool correct;
  final String? topic;
  final String? difficultyLabel;

  Map<String, dynamic> toJson() => {
        'questionId': questionId,
        'subject': subject,
        'correct': correct,
        'topic': topic,
        'difficultyLabel': difficultyLabel,
      };
}

/// Reads the adaptive profile and posts answers back to it.
///
/// The ranking in [rankByFit] is the app's half of the same contract the web
/// implements in `CBTPage.jsx`: the two must agree, or a student would be served
/// questions they have just done on the website. Cached under the same key the
/// web uses so a session started in either place sees the same ability estimate.
class LearningProfileRepository {
  LearningProfileRepository({
    required ApiClient api,
    required FirestoreCache cache,
    FirebaseFirestore? firestore,
  })  : _api = api,
        _cache = cache,
        _db = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirestoreCache _cache;
  final FirebaseFirestore _db;

  static String cacheKeyFor(String uid) => 'mlprofile_$uid';

  Future<LearningProfile> load(String? uid) async {
    if (uid == null || uid.isEmpty) return const LearningProfile();

    return _cache.read<LearningProfile>(
      cacheKeyFor(uid),
      CacheTtl.quickTests,
      () async {
        try {
          final snap = await _db
              .collection('users')
              .doc(uid)
              .collection('ml')
              .doc('profile')
              .get();
          return LearningProfile.fromMap(snap.data() ?? const {});
        } catch (_) {
          // Offline, or the doc has never been written. A neutral profile ranks
          // purely on freshness, which is still better than a blind shuffle.
          return const LearningProfile();
        }
      },
      decode: (json) => LearningProfile.fromMap(
        json is Map ? Map<String, dynamic>.from(json) : const {},
      ),
    );
  }

  /// Draws [count] questions at random from [pool].
  ///
  /// Questions this student has never seen are drawn first, so the bank is
  /// exhausted before anything repeats — but inside a freshness tier the order
  /// is pure chance. Two students sitting the same mode get different papers,
  /// and so does the same student on a second attempt.
  ///
  /// This replaced an Elo "closest to your measured ability" ranking whose
  /// seed ratings came from the admin's Easy/Medium/Hard label. Those labels
  /// were applied inconsistently across uploads, so the ordering was noise
  /// wearing the costume of adaptivity, and being otherwise deterministic it
  /// served the same questions in the same order every sitting. Mirrors
  /// `drawPaper` in the website's `src/pages/CBTPage.jsx`.
  static List<Question> drawPaper(
    List<Question> pool,
    Map<String, SeenQuestion> seen,
    int count,
  ) {
    final byFreshness = <int, List<Question>>{};
    for (final q in pool) {
      final seenCount = (seen[q.id] ?? SeenQuestion.unseen).seenCount;
      byFreshness.putIfAbsent(seenCount, () => []).add(q);
    }

    final picked = <Question>[];
    for (final seenCount in byFreshness.keys.toList()..sort()) {
      if (picked.length >= count) break;
      picked.addAll(byFreshness[seenCount]!..shuffle(_random));
    }
    return picked.take(count).toList();
  }

  static final _random = Random();

  /// Sends a finished sitting's per-question results to the learning engine.
  ///
  /// Best-effort: the sitting is already scored and saved by the time this runs,
  /// and a student on a bad connection must not see an error for it. The cached
  /// profile is dropped on success so the next sitting sees the updated
  /// seen-question map.
  Future<void> recordAnswers(String uid, List<AnswerRecord> answers) async {
    if (answers.isEmpty) return;
    try {
      await _api.post('/cbt/record-answers', {
        'answers': [for (final a in answers) a.toJson()],
      });
      _cache.invalidate(cacheKeyFor(uid));
      _cache.invalidate('mlProfile_$uid');
      _cache.invalidate('subjectCoverage_${uid}_questions');
      _cache.invalidate('subjectCoverage_${uid}_jssQuestions');
    } catch (_) {
      // The raw log is the engine's durable record; losing one batch costs a
      // little adaptivity, not a result.
    }
  }
}
